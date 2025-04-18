use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

pub async fn root() -> &'static str {
    "Hello, World!"
}

#[derive(Deserialize)]
pub struct CreateUser {
    pub username: String,
}

#[derive(Serialize)]
pub struct User {
    pub id: i64,
    pub username: String,
}

pub async fn create_user(
    State(db): State<SqlitePool>,
    Json(payload): Json<CreateUser>,
) -> Result<(StatusCode, Json<User>), (StatusCode, String)> {
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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok((StatusCode::CREATED, Json(user)))
}

// Optional: expose a way to build the full app
pub fn app(db: SqlitePool) -> Router {
    Router::new()
        .route("/", get(root))
        .route("/users", post(create_user))
        .with_state(db)
}
