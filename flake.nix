{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs = {
    flake-utils,
    rust-overlay,
    crane,
    advisory-db,
    nixpkgs,
    ...
  }: let
    perSystemOutputs = flake-utils.lib.eachDefaultSystem (system: let
      pkgs = (import nixpkgs) {
        inherit system;
        overlays = [(import rust-overlay)];
      };
      inherit (pkgs) lib callPackage;
      # Rust toolchain with additional components (rust-src, rust-analyzer)
      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src" "rust-analyzer"];
      };

      # Developer tools used in the devShell (Rust + sqlx CLI)
      devTools = [rustToolchain pkgs.sqlx-cli];

      # Shared build dependencies, including platform-specific ones
      dependencies = with pkgs; [];

      # Native build inputs like pkg-config + platform-specific deps
      nativeBuildInputs = with pkgs; [pkg-config] ++ dependencies;

      # Environment variables used during build
      buildEnvVars = {
        NIX_LDFLAGS = ["-L" "${pkgs.libiconv}/lib"];
      };

      # Builds the main Rust package using crane + extra configuration
      koun = let
        craneLib = crane.mkLib {
          inherit rustToolchain pkgs;
        };

        commonArgs = {
          pname = "koun";
          version = "0.1.0";
          src = craneLib.cleanCargoSource ./.;
          buildInputs = [rustToolchain] ++ nativeBuildInputs;
          buildEnv = buildEnvVars;
          cargoExtraArgs = "--locked";
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        package = craneLib.buildPackage (commonArgs
          // {
            inherit cargoArtifacts;
          });

        checks = {
          clippy = craneLib.cargoClippy (commonArgs // {inherit cargoArtifacts;});
          test = craneLib.cargoNextest (commonArgs // {inherit cargoArtifacts;});
          fmt = craneLib.cargoFmt commonArgs;
          audit = craneLib.cargoAudit (commonArgs
            // {
              RUSTSEC_ADVISORY_DB = advisory-db;
              pkgs = pkgs;
            });
        };
      in {
        inherit package checks;
      };

      # Wraps the package in a flake-compatible CLI app
      app = flake-utils.lib.mkApp {drv = koun.package;};
    in {
      # The default build output (used in `nix build`)
      packages.default = koun.package;

      # The default app output (used in `nix run`)
      apps.default = app;

      # Prebuilt dependencies to be cached using vendorDependencies
      lib.vendorDependencies =
        pkgs.callPackage ./nix/cache.nix {koun = koun.package;};

      # Dev shell with Rust, sqlx, and platform-specific libs
      devShells.default = pkgs.mkShell ({
          nativeBuildInputs = nativeBuildInputs ++ [pkgs.protobuf];
          buildInputs = devTools ++ dependencies;
          DATABASE_URL = "sqlite:./db.sqlite";
        }
        // buildEnvVars);

      # Simple shell command to format all .nix files
      formatter = with pkgs;
        writeShellApplication {
          name = "nixfmt-nix-files";
          runtimeInputs = [fd nixfmt-classic];
          text = "fd \\.nix\\$ --hidden --type f | xargs nixfmt";
        };

      # Check that all Nix files are properly formatted
      checks =
        {
          nix-files-are-formatted = pkgs.stdenvNoCC.mkDerivation {
            name = "fmt-check";
            dontBuild = true;
            src = ./.;
            doCheck = true;
            nativeBuildInputs = with pkgs; [fd nixfmt-classic];
            checkPhase = ''
              set -e
              # find all nix files, and verify that they're formatted correctly
              fd \.nix\$ --hidden --type f | xargs nixfmt -c
            '';
            installPhase = ''
              mkdir "$out"
            '';
          };
        }
        // koun.checks;

      # Add the app as a top-level overlay (can be used by external flakes)
      overlays.default = _final: _prev: {koun = app;};
    });
  in
    # Final flake outputs
    perSystemOutputs
    // {
      # Expose the built app through the flake overlay system
      overlays.default = final: _prev: {
        koun = perSystemOutputs.packages.${final.stdenv.system}.default;
      };
    };
}
