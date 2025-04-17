#![deny(clippy::all)]
#![deny(clippy::pedantic)]
#![deny(clippy::nursery)]

use axum::{
    Json, Router,
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sqlx::sqlite::SqlitePoolOptions;

#[tokio::main]
async fn main() {
    // initialize tracing
    tracing_subscriber::fmt::init();
    println!("good");
    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect("sqlite:./db.sqlite")
        .await
        .unwrap();

    // build our application with a route
    let app = Router::new()
        .with_state(db)
        // `GET /` goes to `root`
        .route("/", get(root))
        // `POST /users` goes to `create_user`
        .route("/users", post(create_user))
        .route("/susers", post(create_user));

    // run our app with hyper, listening globally on port 3000
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// basic handler that responds with a static string
async fn root() -> &'static str {
    "Hello, World!"
}

async fn create_user(
    // this argument tells axum to parse the request body
    // as JSON into a `CreateUser` type
    Json(payload): Json<CreateUser>,
) -> (StatusCode, Json<User>) {
    // insert your application logic here
    let user = User {
        id: 1337,
        username: payload.username,
    };

    // this will be converted into a JSON response
    // with a status code of `201 Created`
    (StatusCode::CREATED, Json(user))
}

// the input to our `create_user` handler
#[derive(Deserialize)]
struct CreateUser {
    username: String,
}

// the output to our `create_user` handler
#[derive(Serialize)]
struct User {
    id: u64,
    username: String,
}
#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Json, http::StatusCode};

    #[tokio::test]
    async fn test_root_mock() {
        let res = root().await;
        assert_eq!(res, "Hello, World!");
    }

    #[tokio::test]
    async fn test_create_user_mock() {
        let input = CreateUser {
            username: "tester".into(),
        };

        let (status, Json(user)) = create_user(Json(input)).await;

        assert_eq!(status, StatusCode::CREATED);
        assert_eq!(user.id, 1337);
        assert_eq!(user.username, "tester");
    }
}
