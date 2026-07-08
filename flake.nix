{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };
    };
    lib = pkgs.lib;

    androidSdk =
      (pkgs.androidenv.composeAndroidPackages {
        platformVersions = ["36" "35" "34"];
        buildToolsVersions = ["36.0.0" "35.0.0" "34.0.0"];
        ndkVersions = ["27.0.12077973"];
        includeNDK = true;
        cmakeVersions = ["3.22.1"];
        includeCmake = true;
        includeEmulator = false;
      }).androidsdk;

    sdkRoot = "${androidSdk}/libexec/android-sdk";

    shell = pkgs.mkShell {
      name = "koun-dev-shell";
      packages = with pkgs; [
        flutter
        dart
        androidSdk
        android-tools
        jdk17
        just
        rustc
        cargo
        clippy
        rustfmt
        pkg-config
        mold
        cargo-watch
        sqlite
        sqlx-cli
        watchexec
        github-copilot-cli
      ];

      RUSTFLAGS = "-C link-arg=-fuse-ld=mold";

      ANDROID_SDK_ROOT = sdkRoot;
      ANDROID_HOME = sdkRoot;
      JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
    };

    webBuild = pkgs.flutter.buildFlutterApplication {
      pname = "koun-web";
      version = "0.1.0";
      src = pkgs.lib.cleanSource ./flutter;
      autoPubspecLock = ./flutter/pubspec.lock;
      targetFlutterPlatform = "web";
    };

    package = pkgs.rustPlatform.buildRustPackage {
      pname = "koun";
      version = "0.1.0";
      src = ./backend;

      cargoLock = {
        lockFile = ./backend/Cargo.lock;
      };

      nativeBuildInputs = with pkgs; [
        pkg-config
      ];

      buildInputs = with pkgs; [
        sqlite
        openssl
      ];

      preBuild = ''
        mkdir -p web_build
        cp -r ${webBuild}/* web_build/
      '';

      doCheck = false;

      meta = with lib; {
        description = "Spaced repetition app backend";
        homepage = "https://github.com/MathieuMoalic/koun";
        license = licenses.gpl3;
        maintainers = [];
      };
    };

    prebuilt = pkgs.stdenvNoCC.mkDerivation {
      pname = "koun";
      version = "0.1.0";

      src = pkgs.fetchurl {
        url = "https://github.com/MathieuMoalic/koun/releases/download/v0.1.0/koun-v0.1.0-x86_64-linux.tar.gz";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };

      sourceRoot = ".";

      installPhase = ''
        install -Dm755 koun-v0.1.0-x86_64-linux $out/bin/koun
      '';

      meta = with lib; {
        description = "Spaced repetition app backend (prebuilt)";
        homepage = "https://github.com/MathieuMoalic/koun";
        license = licenses.gpl3;
        platforms = ["x86_64-linux"];
        maintainers = [];
      };
    };

    service = {
      lib,
      config,
      pkgs,
      ...
    }: let
      cfg = config.services.koun;
    in {
      options.services.koun = {
        enable = lib.mkEnableOption "Koun spaced repetition backend";

        package = lib.mkOption {
          type = lib.types.package;
          default = package;
          description = "The koun package to use.";
        };

        bindAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:8080";
          description = "Address to bind the HTTP server to";
        };

        databasePath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/koun/koun.sqlite";
          description = "Path to SQLite database file";
        };

        logFile = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/koun/koun.log";
          description = "Path to log file";
        };

        corsOrigin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://koun.yourdomain.com";
          description = "CORS allowed origin. If null, allows any origin";
        };

        passwordHash = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Argon2 password hash. Generate with: koun hash-password";
        };

        passwordHashFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing password hash (for sops-nix)";
        };

        jwtSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "JWT secret. If not set, generates a random one.";
        };

        jwtSecretFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing JWT secret (for sops-nix)";
        };

        llmApiKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "LLM API key";
        };

        llmApiKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing LLM API key (for sops-nix)";
        };

        elevenlabsApiKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "ElevenLabs API key";
        };

        elevenlabsApiKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing ElevenLabs API key (for sops-nix)";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.passwordHash != null || cfg.passwordHashFile != null;
            message = "services.koun.passwordHash or services.koun.passwordHashFile must be set";
          }
          {
            assertion = !(cfg.passwordHash != null && cfg.passwordHashFile != null);
            message = "services.koun.passwordHash and services.koun.passwordHashFile are mutually exclusive";
          }
          {
            assertion = !(cfg.jwtSecret != null && cfg.jwtSecretFile != null);
            message = "services.koun.jwtSecret and services.koun.jwtSecretFile are mutually exclusive";
          }
          {
            assertion = !(cfg.llmApiKey != null && cfg.llmApiKeyFile != null);
            message = "services.koun.llmApiKey and services.koun.llmApiKeyFile are mutually exclusive";
          }
          {
            assertion = !(cfg.elevenlabsApiKey != null && cfg.elevenlabsApiKeyFile != null);
            message = "services.koun.elevenlabsApiKey and services.koun.elevenlabsApiKeyFile are mutually exclusive";
          }
        ];

        users.users.koun = {
          isSystemUser = true;
          group = "koun";
          home = "/var/lib/koun";
          createHome = true;
        };
        users.groups.koun = {};

        systemd.tmpfiles.rules = [
          "d ${dirOf cfg.databasePath} 0750 koun koun - -"
          "d ${dirOf cfg.logFile} 0750 koun koun - -"
          "f ${cfg.logFile} 0640 koun koun - -"
        ];

        systemd.services.koun = {
          description = "Koun spaced repetition backend";
          after = ["network.target"];
          wantedBy = ["multi-user.target"];

          script = let
            passwordHashLoader =
              if cfg.passwordHashFile != null
              then ''export KOUN_PASSWORD_HASH="$(cat ${cfg.passwordHashFile})"''
              else "";
            jwtSecretLoader =
              if cfg.jwtSecretFile != null
              then ''export KOUN_JWT_SECRET="$(cat ${cfg.jwtSecretFile})"''
              else "";
            llmApiKeyLoader =
              if cfg.llmApiKeyFile != null
              then ''export KOUN_LLM_API_KEY="$(cat ${cfg.llmApiKeyFile})"''
              else "";
            elevenlabsApiKeyLoader =
              if cfg.elevenlabsApiKeyFile != null
              then ''export KOUN_ELEVENLABS_API_KEY="$(cat ${cfg.elevenlabsApiKeyFile})"''
              else "";
          in ''
            ${passwordHashLoader}
            ${jwtSecretLoader}
            ${llmApiKeyLoader}
            ${elevenlabsApiKeyLoader}
            exec ${cfg.package}/bin/koun
          '';

          serviceConfig = {
            WorkingDirectory = "/var/lib/koun";
            User = "koun";
            Group = "koun";
            StateDirectory = "koun";
            Restart = "always";
            RestartSec = "5s";
            NoNewPrivileges = "yes";
            PrivateTmp = "yes";
            ProtectSystem = "strict";
            ReadWritePaths = [(dirOf cfg.databasePath)];
            SocketBindAllow = let
              port = lib.last (lib.splitString ":" cfg.bindAddr);
            in ["tcp:${port}"];
            SocketBindDeny = "any";
          };
        };
      };
    };
  in {
    devShells.${system}.default = shell;
    nixosModules.koun-service = service;
    packages.${system} = {
      default = package;
      backend = package;
      prebuilt = prebuilt;
      web = webBuild;
    };
  };
}