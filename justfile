default:
    @just --list

backend:
    cd backend && cargo watch -q -c -w src -w Cargo.toml -x 'run -- -v'

android:
    adb reverse tcp:8080 tcp:8080
    cd flutter && flutter run -d CPH2465

web:
    cd flutter && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173

# Build release artifacts, update flake.nix hash, commit, and tag
release TYPE:
    python3 scripts/release.py release "{{TYPE}}"
    just update-server

update-server:
    ssh homeserver "cd /home/mat/nix; nix flake update koun; up"
