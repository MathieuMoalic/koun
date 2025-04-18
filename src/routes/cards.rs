use axum::http::StatusCode;
use axum::{Json, Router, extract::State, routing::get};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

#[derive(Serialize, Deserialize)]
pub struct Card {
    pub front: String,
    pub back: String,
}

pub fn routes(db: SqlitePool) -> Router {
    Router::new().route("/", get(get_all_cards)).with_state(db)
}

async fn get_all_cards(
    State(db): State<SqlitePool>,
) -> Result<(StatusCode, Json<Vec<Card>>), (StatusCode, String)> {
    let cards = sqlx::query_as!(
        Card,
        r#"
        SELECT front, back FROM cards
        "#
    )
    .fetch_all(&db)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Database error: {}", e),
        )
    })?;

    Ok((StatusCode::OK, Json(cards)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use serde_json::from_slice;
    use sqlx::sqlite::SqlitePoolOptions;
    use tower::ServiceExt; // for `app.oneshot`

    #[tokio::test]
    async fn test_get_all_cards_empty() {
        let db = SqlitePoolOptions::new().connect(":memory:").await.unwrap();

        sqlx::migrate!().run(&db).await.unwrap();

        let app = routes(db);

        let response = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let cards: Vec<Card> = serde_json::from_slice(&body).unwrap();

        assert_eq!(cards.len(), 0);
    }

    #[tokio::test]
    async fn test_get_all_cards_after_adding_one() {
        let db = SqlitePoolOptions::new().connect(":memory:").await.unwrap();

        sqlx::migrate!().run(&db).await.unwrap();

        // Insert a test card manually
        sqlx::query("INSERT INTO cards (front, back) VALUES (?, ?)")
            .bind("Bonjour")
            .bind("Hello")
            .execute(&db)
            .await
            .unwrap();

        let app = routes(db);

        let response = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let cards: Vec<Card> = from_slice(&body).unwrap();

        // Assert the inserted card is returned
        assert_eq!(cards.len(), 1);
        assert_eq!(cards[0].front, "Bonjour");
        assert_eq!(cards[0].back, "Hello");
    }
}
