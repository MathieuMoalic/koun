# Bump version (major, minor, or patch)
bump TYPE:
    #!/usr/bin/env bash
    set -euo pipefail

    current=$(grep '^version = ' backend/Cargo.toml | head -1 | sed 's/version = \"\\(.*\\)\"/\\1/')
    IFS='.' read -r major minor patch <<< "$current"

    case "{{TYPE}}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "Error: TYPE must be major, minor, or patch"; exit 1 ;;
    esac

    new_version="$major.$minor.$patch"
    echo "Bumping version: $current → $new_version"

    sed -i "s/^version = \"$current\"/version = \"$new_version\"/" backend/Cargo.toml
    sed -i "s/^version: $current$/version: $new_version/" flutter/pubspec.yaml
    (cd backend && cargo check --quiet)

    git add backend/Cargo.toml backend/Cargo.lock flutter/pubspec.yaml
    git diff --cached
    git commit -m "Bump version to $new_version"
    git tag -a "v$new_version" -m "Release v$new_version"
    echo "✓ Version bumped to $new_version and tagged"

backend:
    cd backend && cargo watch -q -c -w src -w Cargo.toml -x 'run -- -v'

android:
  adb reverse tcp:8080 tcp:8080
  cd flutter && flutter run -d CPH2465

web:
  cd flutter && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173

# Build release artifacts (APK + backend) with version bump
release TYPE:
    #!/usr/bin/env bash
    set -euo pipefail

    current=$(grep '^version = ' backend/Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
    IFS='.' read -r major minor patch <<< "$current"

    case "{{TYPE}}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "Error: TYPE must be major, minor, or patch"; exit 1 ;;
    esac

    new_version="$major.$minor.$patch"
    echo "Bumping version: $current → $new_version"

    sed -i "s/^version = \"$current\"/version = \"$new_version\"/" backend/Cargo.toml
    sed -i "s/^version: $current$/version: $new_version/" flutter/pubspec.yaml
    sed -i "s/^version: \"$current\"$/version: \"$new_version\"/" flutter/pubspec.yaml
    (cd backend && cargo check --quiet)

    git add backend/Cargo.toml backend/Cargo.lock flutter/pubspec.yaml
    git commit -m "Bump version to $new_version"
    git tag -a "v$new_version" -m "Release v$new_version"

    echo "✓ Version bumped to $new_version and tagged"

    echo "Creating release v$new_version"
    mkdir -p release/artifacts
    rm -rf release/artifacts/*

    BACKEND_NAME="koun-v$new_version-x86_64-linux"

    (cd backend && cargo build --release --locked)
    cp backend/target/release/koun release/artifacts/$BACKEND_NAME
    strip release/artifacts/$BACKEND_NAME || true
    tar -czf release/artifacts/$BACKEND_NAME.tar.gz -C release/artifacts $BACKEND_NAME
    sha256sum release/artifacts/$BACKEND_NAME.tar.gz > release/artifacts/SHA256SUMS.txt

    (cd flutter && flutter pub get)
    (cd flutter && flutter build apk --flavor prod --release --build-name "$new_version" --build-number "$(git rev-list --count HEAD)")

    cp flutter/build/app/outputs/flutter-apk/app-prod-release.apk release/artifacts/koun-v$new_version.apk

    echo ""
    echo "📦 Release artifacts created:"
    ls -lh release/artifacts/

    echo ""
    echo "To push to GitHub:"
    echo "  just push-release v$new_version"

# Push release artifacts to GitHub
push-release TAG:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v gh &> /dev/null; then
        echo "Error: 'gh' (GitHub CLI) is not installed"
        exit 1
    fi

    gh release create "{{TAG}}" --generate-notes -- release/artifacts/*
