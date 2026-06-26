use axum::{Json, extract::State, http::StatusCode};
use serde::Serialize;
use sqlx::sqlite::SqliteQueryResult;

use crate::error::AppResult;
use crate::models::{
    AppState, CardWithDue, ReviewRating, ReviewSyncRequest, ReviewSyncResponse, ScheduleState,
    now_ts,
};
use crate::routes::settings::get_fsrs_config;
use crate::scheduling::apply_fsrs;

#[derive(Serialize)]
pub struct NextReviewResponse {
    pub next: Option<CardWithDue>,
    pub due_count: i64,
}

pub async fn next_review(State(state): State<AppState>) -> AppResult<Json<NextReviewResponse>> {
    let now = now_ts();

    let due_count: i64 = sqlx::query_scalar(&format!(
        "SELECT COUNT(*) FROM schedule_state
         JOIN cards ON cards.id = schedule_state.card_id
         WHERE cards.suspended = 0 AND fsrs_due_at <= ?",
    ))
    .bind(now)
    .fetch_one(&state.pool)
    .await?;

    #[derive(sqlx::FromRow)]
    struct CardDueRow {
        id: i64,
        front: String,
        back: String,
        hint: Option<String>,
        card_type: String,
        suspended: bool,
        created_at: i64,
        updated_at: i64,
        due_at: i64,
    }

    let next_card = sqlx::query_as::<_, CardDueRow>(
        &format!(
            "SELECT cards.id, cards.front, cards.back, cards.hint, cards.card_type, cards.suspended, cards.created_at, cards.updated_at,
                    schedule_state.fsrs_due_at as due_at
             FROM cards
             JOIN schedule_state ON schedule_state.card_id = cards.id
             WHERE cards.suspended = 0 AND fsrs_due_at <= ?
             ORDER BY fsrs_due_at ASC
             LIMIT 1",
        ),
    )
    .bind(now)
    .fetch_optional(&state.pool)
    .await?;

    let next = next_card.map(|row| CardWithDue {
        due_at: row.due_at,
        card: crate::models::Card {
            id: row.id,
            front: row.front,
            back: row.back,
            hint: row.hint,
            card_type: row.card_type,
            suspended: row.suspended,
            created_at: row.created_at,
            updated_at: row.updated_at,
        },
    });

    Ok(Json(NextReviewResponse { next, due_count }))
}

pub async fn sync_reviews(
    State(state): State<AppState>,
    Json(req): Json<ReviewSyncRequest>,
) -> AppResult<Json<ReviewSyncResponse>> {
    let fsrs_config = get_fsrs_config(&state.pool).await?;
    let mut tx = state.pool.begin().await?;
    let mut processed = 0;

    for event in req.events {
        let reviewed_at = event.reviewed_at.unwrap_or_else(now_ts);
        let mut schedule = fetch_schedule_state(&mut tx, event.card_id).await?;
        apply_review(&mut schedule, event.rating, reviewed_at, &fsrs_config);
        update_schedule_state(&mut tx, &schedule).await?;
        update_card_timestamp(&mut tx, event.card_id, reviewed_at).await?;
        insert_review(&mut tx, event.card_id, event.rating, reviewed_at).await?;
        processed += 1;
    }

    tx.commit().await?;

    Ok(Json(ReviewSyncResponse { processed }))
}

fn apply_review(
    schedule: &mut ScheduleState,
    rating: ReviewRating,
    reviewed_at: i64,
    fsrs_config: &crate::scheduling::FsrsConfig,
) {
    apply_fsrs(schedule, rating, reviewed_at, fsrs_config);
    schedule.updated_at = reviewed_at;
}

async fn fetch_schedule_state(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_id: i64,
) -> AppResult<ScheduleState> {
    let state = sqlx::query_as::<_, ScheduleState>(
        "SELECT card_id, fsrs_stability, fsrs_difficulty, fsrs_due_at, fsrs_last_review_at,
                fsrs_learning_step, fsrs_relearning_step, updated_at
         FROM schedule_state WHERE card_id = ?",
    )
    .bind(card_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;

    Ok(state)
}

async fn update_schedule_state(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    schedule: &ScheduleState,
) -> AppResult<SqliteQueryResult> {
    let result = sqlx::query(
        "UPDATE schedule_state SET
            fsrs_stability = ?,
            fsrs_difficulty = ?,
            fsrs_due_at = ?,
            fsrs_last_review_at = ?,
            fsrs_learning_step = ?,
            fsrs_relearning_step = ?,
            updated_at = ?
         WHERE card_id = ?",
    )
    .bind(schedule.fsrs_stability)
    .bind(schedule.fsrs_difficulty)
    .bind(schedule.fsrs_due_at)
    .bind(schedule.fsrs_last_review_at)
    .bind(schedule.fsrs_learning_step)
    .bind(schedule.fsrs_relearning_step)
    .bind(schedule.updated_at)
    .bind(schedule.card_id)
    .execute(&mut **tx)
    .await?;

    Ok(result)
}

async fn update_card_timestamp(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_id: i64,
    updated_at: i64,
) -> AppResult<SqliteQueryResult> {
    let result = sqlx::query("UPDATE cards SET updated_at = ? WHERE id = ?")
        .bind(updated_at)
        .bind(card_id)
        .execute(&mut **tx)
        .await?;
    Ok(result)
}

async fn insert_review(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_id: i64,
    rating: ReviewRating,
    reviewed_at: i64,
) -> AppResult<SqliteQueryResult> {
    let result = sqlx::query(
        "INSERT INTO reviews (card_id, rating, reviewed_at)
         VALUES (?, ?, ?)",
    )
    .bind(card_id)
    .bind(rating_to_str(rating))
    .bind(reviewed_at)
    .execute(&mut **tx)
    .await?;
    Ok(result)
}

fn rating_to_str(rating: ReviewRating) -> &'static str {
    match rating {
        ReviewRating::Again => "again",
        ReviewRating::Hard => "hard",
        ReviewRating::Good => "good",
        ReviewRating::Easy => "easy",
    }
}
