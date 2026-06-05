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
  in {
    devShells.${system}.default = pkgs.mkShell {
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
  };
}
