use axum::{Json, extract::{Path, State}, http::StatusCode};
use serde::Deserialize;
use sqlx::SqlitePool;

use crate::error::AppResult;
use crate::models::{AppState, Card, CardListItem, now_ts};
use crate::scheduling::fsrs_retrievability;

#[derive(Deserialize)]
pub struct CreateCardReq {
    pub front: String,
    pub back: String,
    pub hint: Option<String>,
}

#[derive(Deserialize)]
pub struct UpdateCardReq {
    pub front: Option<String>,
    pub back: Option<String>,
    pub hint: Option<String>,
    pub suspended: Option<bool>,
}

pub async fn list_cards(State(state): State<AppState>) -> AppResult<Json<Vec<CardListItem>>> {
    #[derive(sqlx::FromRow)]
    struct CardListRow {
        id: i64,
        front: String,
        back: String,
        hint: Option<String>,
        suspended: bool,
        created_at: i64,
        updated_at: i64,
        fsrs_stability: f64,
        fsrs_difficulty: f64,
        fsrs_due_at: i64,
        fsrs_last_review_at: i64,
    }

    let rows = sqlx::query_as::<_, CardListRow>(
        "SELECT cards.id, cards.front, cards.back, cards.hint, cards.suspended, cards.created_at, cards.updated_at,
                schedule_state.fsrs_stability, schedule_state.fsrs_difficulty,
                schedule_state.fsrs_due_at, schedule_state.fsrs_last_review_at
         FROM cards
         JOIN schedule_state ON schedule_state.card_id = cards.id
         ORDER BY cards.created_at DESC",
    )
    .fetch_all(&state.pool)
    .await?;

    let now = now_ts();
    let cards = rows
        .into_iter()
        .map(|row| CardListItem {
            id: row.id,
            front: row.front,
            back: row.back,
            hint: row.hint,
            suspended: row.suspended,
            created_at: row.created_at,
            updated_at: row.updated_at,
            fsrs_stability: row.fsrs_stability,
            fsrs_difficulty: row.fsrs_difficulty,
            fsrs_due_at: row.fsrs_due_at,
            fsrs_last_review_at: row.fsrs_last_review_at,
            fsrs_retrievability: fsrs_retrievability(
                row.fsrs_stability,
                row.fsrs_last_review_at,
                now,
            ),
        })
        .collect();

    Ok(Json(cards))
}

pub async fn create_card(
    State(state): State<AppState>,
    Json(req): Json<CreateCardReq>,
) -> AppResult<Json<Card>> {
    let now = now_ts();
    let card = sqlx::query_as::<_, Card>(
        "INSERT INTO cards (front, back, hint, suspended, created_at, updated_at)
         VALUES (?, ?, ?, 0, ?, ?)
         RETURNING id, front, back, hint, suspended, created_at, updated_at",
    )
    .bind(req.front)
    .bind(req.back)
    .bind(req.hint)
    .bind(now)
    .bind(now)
    .fetch_one(&state.pool)
    .await?;

    insert_schedule_state(&state.pool, card.id, now).await?;

    Ok(Json(card))
}

pub async fn update_card(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Json(req): Json<UpdateCardReq>,
) -> AppResult<Json<Card>> {
    let existing = sqlx::query_as::<_, Card>(
        "SELECT id, front, back, hint, suspended, created_at, updated_at FROM cards WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;

    let front = req.front.unwrap_or(existing.front);
    let back = req.back.unwrap_or(existing.back);
    let hint = req.hint.or(existing.hint);
    let suspended = req.suspended.unwrap_or(existing.suspended);
    let now = now_ts();

    let updated = sqlx::query_as::<_, Card>(
        "UPDATE cards SET front = ?, back = ?, hint = ?, suspended = ?, updated_at = ?
         WHERE id = ?
         RETURNING id, front, back, hint, suspended, created_at, updated_at",
    )
    .bind(front)
    .bind(back)
    .bind(hint)
    .bind(suspended)
    .bind(now)
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(updated))
}

pub async fn delete_card(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<StatusCode> {
    let result = sqlx::query("DELETE FROM cards WHERE id = ?")
        .bind(id)
        .execute(&state.pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(StatusCode::NOT_FOUND.into());
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn insert_schedule_state(pool: &SqlitePool, card_id: i64, now: i64) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO schedule_state (
            card_id,
            fsrs_stability, fsrs_difficulty, fsrs_due_at, fsrs_last_review_at,
            fsrs_learning_step, fsrs_relearning_step, updated_at
         )
         VALUES (?, 1.0, 5.0, ?, 0, 0, 0, ?)",
    )
    .bind(card_id)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}
