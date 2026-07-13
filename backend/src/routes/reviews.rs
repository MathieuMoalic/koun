use axum::{Json, extract::State, http::StatusCode};
use serde::Serialize;
use sqlx::sqlite::SqliteQueryResult;

use crate::error::AppResult;
use crate::models::{
    AppState, ReviewDirection, ReviewItem, ReviewRating, ReviewSyncRequest, ReviewSyncResponse,
    ScheduleState, now_ts,
};
use crate::routes::settings::get_fsrs_config;
use crate::scheduling::apply_fsrs;

const UNLOCK_INTERVAL_SECS: i64 = 3 * 24 * 3600;

#[derive(Serialize)]
pub struct NextReviewResponse {
    pub next: Option<ReviewItem>,
    pub due_count: i64,
    pub new_cards_learned: i64,
    pub old_cards_reviewed: i64,
}

pub async fn next_review(State(state): State<AppState>) -> AppResult<Json<NextReviewResponse>> {
    let now = now_ts();

    let due_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM schedule_state
         JOIN card_directions ON card_directions.id = schedule_state.card_direction_id
         JOIN cards ON cards.id = card_directions.card_id
         WHERE cards.suspended = 0
           AND card_directions.enabled = 1
           AND schedule_state.fsrs_due_at <= ?",
    )
    .bind(now)
    .fetch_one(&state.pool)
    .await?;

let daily_totals = sqlx::query_scalar::<_, i64>(
    "SELECT COALESCE(SUM(new_cards_learned), 0) FROM schedule_state
     JOIN card_directions ON card_directions.id = schedule_state.card_direction_id
     JOIN cards ON cards.id = card_directions.card_id
     WHERE cards.suspended = 0
       AND card_directions.enabled = 1
       AND schedule_state.fsrs_due_at <= ?",
)
.bind(now)
.fetch_one(&state.pool)
.await?;

let old_cards_reviewed = sqlx::query_scalar::<_, i64>(
    "SELECT COALESCE(SUM(old_cards_reviewed), 0) FROM schedule_state
     JOIN card_directions ON card_directions.id = schedule_state.card_direction_id
     JOIN cards ON cards.id = card_directions.card_id
     WHERE cards.suspended = 0
       AND card_directions.enabled = 1
       AND schedule_state.fsrs_due_at <= ?",
)
.bind(now)
.fetch_one(&state.pool)
.await?;

    #[derive(sqlx::FromRow)]
    struct DueRow {
        card_id: i64,
        card_direction_id: i64,
        direction: String,
        prompt: String,
        answer: String,
        hint: Option<String>,
        card_type: String,
        due_at: i64,
    }

    let next_due = sqlx::query_as::<_, DueRow>(
        "SELECT
            cards.id AS card_id,
            card_directions.id AS card_direction_id,
            card_directions.direction AS direction,
            CASE
                WHEN card_directions.direction = 'pl_to_en' THEN cards.front
                ELSE cards.back
            END AS prompt,
            CASE
                WHEN card_directions.direction = 'pl_to_en' THEN cards.back
                ELSE cards.front
            END AS answer,
            cards.hint,
            cards.card_type,
            schedule_state.fsrs_due_at AS due_at
         FROM schedule_state
         JOIN card_directions ON card_directions.id = schedule_state.card_direction_id
         JOIN cards ON cards.id = card_directions.card_id
         WHERE cards.suspended = 0
           AND card_directions.enabled = 1
           AND schedule_state.fsrs_due_at <= ?
         ORDER BY schedule_state.fsrs_due_at ASC
         LIMIT 1",
    )
    .bind(now)
    .fetch_optional(&state.pool)
    .await?;

    let next = match next_due {
        Some(row) => Some(ReviewItem {
            card_id: row.card_id,
            card_direction_id: row.card_direction_id,
            direction: parse_direction(&row.direction)?,
            prompt: row.prompt,
            answer: row.answer,
            hint: row.hint,
            card_type: row.card_type,
            due_at: row.due_at,
        }),
        None => None,
    };

    Ok(Json(NextReviewResponse {
        next,
        due_count,
        new_cards_learned: daily_totals,
        old_cards_reviewed: old_cards_reviewed,
    }))
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
        let card_direction_id = resolve_card_direction_id(&mut tx, &event).await?;
        let review_target = fetch_review_target(&mut tx, card_direction_id).await?;
        let mut schedule = review_target.schedule;
        apply_review(&mut schedule, event.rating, reviewed_at, &fsrs_config);
        update_schedule_state(&mut tx, &schedule).await?;
        update_card_timestamp(&mut tx, schedule.card_direction_id, reviewed_at).await?;
        update_review_counters(&mut tx, schedule.card_direction_id, &schedule).await?;
        insert_review(
            &mut tx,
            schedule.card_direction_id,
            event.rating,
            reviewed_at,
        )
        .await?;
        maybe_unlock_reverse_direction(
            &mut tx,
            review_target.card_id,
            review_target.direction,
            event.rating,
            reviewed_at,
            schedule.fsrs_due_at,
        )
        .await?;
        processed += 1;
    }

    tx.commit().await?;

    Ok(Json(ReviewSyncResponse { processed }))
}

#[derive(Debug)]
struct ReviewTarget {
    card_id: i64,
    direction: ReviewDirection,
    schedule: ScheduleState,
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

fn parse_direction(direction: &str) -> AppResult<ReviewDirection> {
    match direction {
        "pl_to_en" => Ok(ReviewDirection::PlToEn),
        "en_to_pl" => Ok(ReviewDirection::EnToPl),
        _ => Err(StatusCode::INTERNAL_SERVER_ERROR.into()),
    }
}

async fn resolve_card_direction_id(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    event: &crate::models::ReviewEvent,
) -> AppResult<i64> {
    if let Some(card_direction_id) = event.card_direction_id {
        return Ok(card_direction_id);
    }

    let Some(card_id) = event.card_id else {
        return Err(StatusCode::BAD_REQUEST.into());
    };

    let direction_id = sqlx::query_scalar::<_, i64>(
        "SELECT id FROM card_directions
         WHERE card_id = ? AND direction = 'pl_to_en'",
    )
    .bind(card_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;

    Ok(direction_id)
}

async fn fetch_review_target(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_direction_id: i64,
) -> AppResult<ReviewTarget> {
    #[derive(sqlx::FromRow)]
    struct ReviewTargetRow {
        card_direction_id: i64,
        card_id: i64,
        direction: String,
        fsrs_stability: f64,
        fsrs_difficulty: f64,
        fsrs_due_at: i64,
        fsrs_last_review_at: i64,
        fsrs_learning_step: i64,
        fsrs_relearning_step: i64,
        updated_at: i64,
        new_cards_learned: i64,
        old_cards_reviewed: i64,
    }

    let row = sqlx::query_as::<_, ReviewTargetRow>(
        "SELECT
            schedule_state.card_direction_id,
            card_directions.card_id,
            card_directions.direction,
            schedule_state.fsrs_stability,
            schedule_state.fsrs_difficulty,
            schedule_state.fsrs_due_at,
            schedule_state.fsrs_last_review_at,
            schedule_state.fsrs_learning_step,
            schedule_state.fsrs_relearning_step,
            schedule_state.updated_at,
            schedule_state.new_cards_learned,
            schedule_state.old_cards_reviewed
          FROM schedule_state
          JOIN card_directions ON card_directions.id = schedule_state.card_direction_id
          WHERE schedule_state.card_direction_id = ?",
    )
    .bind(card_direction_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;

    Ok(ReviewTarget {
        card_id: row.card_id,
        direction: parse_direction(&row.direction)?,
        schedule: ScheduleState {
            card_direction_id: row.card_direction_id,
            fsrs_stability: row.fsrs_stability,
            fsrs_difficulty: row.fsrs_difficulty,
            fsrs_due_at: row.fsrs_due_at,
            fsrs_last_review_at: row.fsrs_last_review_at,
            fsrs_learning_step: row.fsrs_learning_step,
            fsrs_relearning_step: row.fsrs_relearning_step,
            updated_at: row.updated_at,
            new_cards_learned: row.new_cards_learned,
            old_cards_reviewed: row.old_cards_reviewed,
        },
    })
}

async fn update_review_counters(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_direction_id: i64,
    schedule: &ScheduleState,
) -> AppResult<()> {
    let increment_count = if schedule.fsrs_last_review_at > 0 {
        "UPDATE schedule_state SET old_cards_reviewed = old_cards_reviewed + 1 WHERE card_direction_id = ?"
    } else {
        "UPDATE schedule_state SET new_cards_learned = new_cards_learned + 1, old_cards_reviewed = old_cards_reviewed + 1 WHERE card_direction_id = ?"
    };
    sqlx::query(increment_count).bind(card_direction_id).execute(&mut **tx).await?;
    Ok(())
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
            updated_at = ?,
            new_cards_learned = ?,
            old_cards_reviewed = ?
          WHERE card_direction_id = ?",
    )
    .bind(schedule.fsrs_stability)
    .bind(schedule.fsrs_difficulty)
    .bind(schedule.fsrs_due_at)
    .bind(schedule.fsrs_last_review_at)
    .bind(schedule.fsrs_learning_step)
    .bind(schedule.fsrs_relearning_step)
    .bind(schedule.updated_at)
    .bind(schedule.new_cards_learned)
    .bind(schedule.old_cards_reviewed)
    .bind(schedule.card_direction_id)
    .execute(&mut **tx)
    .await?;

    Ok(result)
}

async fn update_card_timestamp(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_direction_id: i64,
    updated_at: i64,
) -> AppResult<SqliteQueryResult> {
    let result = sqlx::query(
        "UPDATE cards
         SET updated_at = ?
         WHERE id = (
            SELECT card_id FROM card_directions WHERE id = ?
         )",
    )
    .bind(updated_at)
    .bind(card_direction_id)
    .execute(&mut **tx)
    .await?;
    Ok(result)
}

async fn insert_review(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_direction_id: i64,
    rating: ReviewRating,
    reviewed_at: i64,
) -> AppResult<SqliteQueryResult> {
    let result = sqlx::query(
        "INSERT INTO reviews (card_direction_id, rating, reviewed_at)
         VALUES (?, ?, ?)",
    )
    .bind(card_direction_id)
    .bind(rating_to_str(rating))
    .bind(reviewed_at)
    .execute(&mut **tx)
    .await?;
    Ok(result)
}

async fn maybe_unlock_reverse_direction(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    card_id: i64,
    direction: ReviewDirection,
    rating: ReviewRating,
    reviewed_at: i64,
    next_due_at: i64,
) -> AppResult<()> {
    if direction != ReviewDirection::PlToEn {
        return Ok(());
    }

    if !matches!(rating, ReviewRating::Good | ReviewRating::Easy) {
        return Ok(());
    }

    let next_interval_secs = next_due_at - reviewed_at;
    if next_interval_secs < UNLOCK_INTERVAL_SECS {
        return Ok(());
    }

    let en_to_pl_direction_id = sqlx::query_scalar::<_, i64>(
        "INSERT INTO card_directions (card_id, direction, enabled, created_at, updated_at)
         VALUES (?, 'en_to_pl', 1, ?, ?)
         ON CONFLICT(card_id, direction) DO UPDATE
            SET enabled = 1,
                updated_at = excluded.updated_at
         RETURNING id",
    )
    .bind(card_id)
    .bind(reviewed_at)
    .bind(reviewed_at)
    .fetch_one(&mut **tx)
    .await?;

sqlx::query(
        "INSERT INTO schedule_state (
            card_direction_id,
            fsrs_stability,
            fsrs_difficulty,
            fsrs_due_at,
            fsrs_last_review_at,
            fsrs_learning_step,
            fsrs_relearning_step,
            updated_at,
            new_cards_learned,
            old_cards_reviewed
          )
          VALUES (?, 1.0, 6.0, ?, 0, 0, 0, ?, 0, 0)
          ON CONFLICT(card_direction_id) DO NOTHING",
    )
    .bind(en_to_pl_direction_id)
    .bind(reviewed_at)
    .bind(reviewed_at)
    .execute(&mut **tx)
    .await?;

    Ok(())
}

fn rating_to_str(rating: ReviewRating) -> &'static str {
    match rating {
        ReviewRating::Again => "again",
        ReviewRating::Hard => "hard",
        ReviewRating::Good => "good",
        ReviewRating::Easy => "easy",
    }
}
