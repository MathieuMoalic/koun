use axum::body::Body;
use axum::{
    Router,
    body::to_bytes,
    http::{Request, StatusCode},
    routing::{get, post},
};
use serde_json::json;
use sqlx::sqlite::SqlitePoolOptions;
use tower::ServiceExt;

use koun::{create_user, root};

async fn setup_app() -> Router {
    // In-memory DB for testing
    let db = SqlitePoolOptions::new().connect(":memory:").await.unwrap();

    sqlx::migrate!().run(&db).await.unwrap();

    Router::new()
        .route("/", get(root))
        .route("/users", post(create_user))
        .with_state(db)
}

#[tokio::test]
async fn test_root_returns_hello() {
    let app = setup_app().await;

    let response = app
        .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(body, "Hello, World!");
}

#[tokio::test]
async fn test_create_user() {
    let app = setup_app().await;

    let payload = json!({ "username": "tester" });

    let request = Request::builder()
        .method("POST")
        .uri("/users")
        .header("content-type", "application/json")
        .body(Body::from(payload.to_string()))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["username"], "tester");
    assert!(json["id"].as_i64().is_some());
}
