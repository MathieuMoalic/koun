#![deny(clippy::all)]
#![deny(clippy::pedantic)]
#![deny(clippy::nursery)]

use anyhow::{Context, Ok, Result};
use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sqlx::{SqlitePool, sqlite::SqlitePoolOptions};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect("sqlite:./db.sqlite")
        .await
        .expect("DB connection failed");

    // Ensure the `users` table exists
    sqlx::query(
        r"
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE
        )
        ",
    )
    .execute(&db)
    .await
    .expect("Failed to create users table");

    let app = Router::new()
        .route("/", get(root))
        .route("/users", post(create_user))
        .with_state(db);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.context("Server error")?;
    Ok(())
}

async fn root() -> &'static str {
    "Hello, World!"
}

async fn create_user(
    State(db): State<SqlitePool>,
    Json(payload): Json<CreateUser>,
) -> Result<(StatusCode, Json<User>), (StatusCode, String)> {
    let result = async {
        let user = sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (username)
            VALUES (?)
            RETURNING id, username
            "#,
            payload.username
        )
        .fetch_one(&db)
        .await
        .context("Failed to insert user")?;

        Ok((StatusCode::CREATED, Json(user)))
    }
    .await;

    result.map_err(|err| (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()))
}

#[derive(Deserialize)]
struct CreateUser {
    username: String,
}

#[derive(Serialize)]
struct User {
    id: i64,
    username: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_root_mock() {
        let res = root().await;
        assert_eq!(res, "Hello, World!");
    }

    #[tokio::test]
    async fn test_create_user_mock() {
        let _input = CreateUser {
            username: "tester".into(),
        };
    }
}
