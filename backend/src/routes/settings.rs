use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::error::AppResult;
use crate::models::{AppState, FsrsSettings};
use crate::scheduling::FsrsConfig;

const DEFAULT_RETENTION: f64 = 0.9;
const DEFAULT_LEARNING_STEP_1_MINUTES: i64 = 1;
const DEFAULT_LEARNING_STEP_2_MINUTES: i64 = 10;
const DEFAULT_RELEARNING_STEP_MINUTES: i64 = 10;

#[derive(sqlx::FromRow)]
struct FsrsSettingsRow {
    desired_retention: f64,
    learning_step_1_minutes: i64,
    learning_step_2_minutes: i64,
    relearning_step_minutes: i64,
}

#[derive(Serialize, Deserialize)]
pub struct FsrsSettingsPayload {
    desired_retention: f64,
    learning_step_1_minutes: i64,
    learning_step_2_minutes: i64,
    relearning_step_minutes: i64,
}

pub async fn get_fsrs_settings(State(state): State<AppState>) -> AppResult<Json<FsrsSettings>> {
    let row = fetch_settings(&state.pool).await?;
    Ok(Json(FsrsSettings {
        desired_retention: row.desired_retention,
        learning_step_1_minutes: row.learning_step_1_minutes,
        learning_step_2_minutes: row.learning_step_2_minutes,
        relearning_step_minutes: row.relearning_step_minutes,
    }))
}

pub async fn set_fsrs_settings(
    State(state): State<AppState>,
    Json(payload): Json<FsrsSettingsPayload>,
) -> AppResult<Json<FsrsSettings>> {
    validate_retention(payload.desired_retention)?;
    validate_minutes(payload.learning_step_1_minutes, "learning_step_1_minutes")?;
    validate_minutes(payload.learning_step_2_minutes, "learning_step_2_minutes")?;
    validate_minutes(payload.relearning_step_minutes, "relearning_step_minutes")?;

    sqlx::query(
        "INSERT INTO fsrs_settings (id, desired_retention, learning_step_1_minutes, learning_step_2_minutes, relearning_step_minutes)
         VALUES (1, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET desired_retention = excluded.desired_retention,
             learning_step_1_minutes = excluded.learning_step_1_minutes,
             learning_step_2_minutes = excluded.learning_step_2_minutes,
             relearning_step_minutes = excluded.relearning_step_minutes",
    )
    .bind(payload.desired_retention)
    .bind(payload.learning_step_1_minutes)
    .bind(payload.learning_step_2_minutes)
    .bind(payload.relearning_step_minutes)
    .execute(&state.pool)
    .await?;

    Ok(Json(FsrsSettings {
        desired_retention: payload.desired_retention,
        learning_step_1_minutes: payload.learning_step_1_minutes,
        learning_step_2_minutes: payload.learning_step_2_minutes,
        relearning_step_minutes: payload.relearning_step_minutes,
    }))
}

pub async fn get_fsrs_config(pool: &SqlitePool) -> AppResult<FsrsConfig> {
    let row = fetch_settings(pool).await?;
    let learning_steps = vec![
        row.learning_step_1_minutes * 60,
        row.learning_step_2_minutes * 60,
    ];
    let relearning_steps = vec![row.relearning_step_minutes * 60];

    validate_retention(row.desired_retention)?;
    validate_step_seconds(&learning_steps, "learning_steps")?;
    validate_step_seconds(&relearning_steps, "relearning_steps")?;

    Ok(FsrsConfig {
        desired_retention: row.desired_retention,
        learning_steps,
        relearning_steps,
    })
}

async fn fetch_settings(pool: &SqlitePool) -> AppResult<FsrsSettingsRow> {
    let row = sqlx::query_as::<_, FsrsSettingsRow>(
        "SELECT desired_retention, learning_step_1_minutes, learning_step_2_minutes, relearning_step_minutes
         FROM fsrs_settings WHERE id = 1",
    )
    .fetch_optional(pool)
    .await?;

    if let Some(row) = row {
        return Ok(row);
    }

    let defaults = default_settings_row();
    sqlx::query(
        "INSERT INTO fsrs_settings (id, desired_retention, learning_step_1_minutes, learning_step_2_minutes, relearning_step_minutes)
         VALUES (1, ?, ?, ?, ?)",
    )
    .bind(defaults.desired_retention)
    .bind(defaults.learning_step_1_minutes)
    .bind(defaults.learning_step_2_minutes)
    .bind(defaults.relearning_step_minutes)
    .execute(pool)
    .await?;

    Ok(defaults)
}

fn validate_retention(retention: f64) -> AppResult<()> {
    if !(0.7..=0.97).contains(&retention) {
        return Err(StatusCode::BAD_REQUEST.into());
    }
    Ok(())
}

fn validate_minutes(minutes: i64, field: &str) -> AppResult<()> {
    if minutes <= 0 {
        tracing::warn!(field = %field, minutes = %minutes, "Invalid FSRS step minutes");
        return Err(StatusCode::BAD_REQUEST.into());
    }
    Ok(())
}

fn validate_step_seconds(steps: &[i64], field: &str) -> AppResult<()> {
    if steps.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }
    for step in steps {
        if *step <= 0 {
            tracing::warn!(field = %field, step = %step, "Invalid FSRS step seconds");
            return Err(StatusCode::BAD_REQUEST.into());
        }
    }
    Ok(())
}

fn default_settings_row() -> FsrsSettingsRow {
    FsrsSettingsRow {
        desired_retention: DEFAULT_RETENTION,
        learning_step_1_minutes: DEFAULT_LEARNING_STEP_1_MINUTES,
        learning_step_2_minutes: DEFAULT_LEARNING_STEP_2_MINUTES,
        relearning_step_minutes: DEFAULT_RELEARNING_STEP_MINUTES,
    }
}
