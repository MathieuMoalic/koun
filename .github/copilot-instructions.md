# Copilot instructions

## Build, test, lint

### Backend (Rust/Axum)

```bash
cd backend
cargo run -- -v
cargo test
cargo test <test_name>
cargo clippy -- -D warnings
```

### Flutter

```bash
cd flutter
flutter pub get
flutter run -d <device-id>        # Android (use `adb reverse tcp:8080 tcp:8080` first)
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173
flutter analyze
flutter test
flutter test test/<file>_test.dart
```

## High-level architecture

- **Repo layout** mirrors `mont`: `backend/` (Rust Axum + SQLite via sqlx) and `flutter/` (Material app, Android-first with a lower-priority web build).
- **Backend** exposes REST endpoints for auth, cards, reviews, stats, and settings. Single-password JWT auth; scheduling logic lives in `backend/src/scheduling.rs`, and state is stored in `schedule_state`.
- **Flutter** uses a bottom-tab shell (Learn/Add/Settings) and `ApiClient` (`flutter/lib/src/api.dart`) for all HTTP calls. Offline review events are queued locally and synced later.
- **Web build** is embedded into the backend via `rust-embed` from `backend/web_build/`.

## Key conventions

- **Env vars**: backend config is `KOUN_*` (see `backend/.env.example`).
- **Auth**: single password hash (Argon2) with access/refresh tokens.
- **Scheduling**: algorithm choice stored in `settings` table; algorithms are SM-2, FSRS, and Leitner.
