use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::error::AppResult;
use crate::models::{AppState, FsrsSettings};
use crate::scheduling::FsrsConfig;

const DEFAULT_RETENTION: f64 = 0.9;
const DEFAULT_LEARNING_STEPS: [&str; 2] = ["1m", "10m"];
const DEFAULT_RELEARNING_STEPS: [&str; 1] = ["10m"];

#[derive(sqlx::FromRow)]
struct FsrsSettingsRow {
    desired_retention: f64,
    learning_steps: String,
    relearning_steps: String,
}

#[derive(Serialize, Deserialize)]
pub struct FsrsSettingsPayload {
    desired_retention: f64,
    learning_steps: Vec<String>,
    relearning_steps: Vec<String>,
}

pub async fn get_fsrs_settings(
    State(state): State<AppState>,
) -> AppResult<Json<FsrsSettings>> {
    let row = fetch_settings(&state.pool).await?;
    Ok(Json(FsrsSettings {
        desired_retention: row.desired_retention,
        learning_steps: parse_steps_json(&row.learning_steps)?,
        relearning_steps: parse_steps_json(&row.relearning_steps)?,
    }))
}

pub async fn set_fsrs_settings(
    State(state): State<AppState>,
    Json(payload): Json<FsrsSettingsPayload>,
) -> AppResult<Json<FsrsSettings>> {
    validate_retention(payload.desired_retention)?;
    validate_steps(&payload.learning_steps, "learning_steps")?;
    validate_steps(&payload.relearning_steps, "relearning_steps")?;

    let learning_json = serde_json::to_string(&payload.learning_steps)
        .map_err(|_| StatusCode::BAD_REQUEST)?;
    let relearning_json = serde_json::to_string(&payload.relearning_steps)
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    sqlx::query(
        "INSERT INTO fsrs_settings (id, desired_retention, learning_steps, relearning_steps)
         VALUES (1, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET desired_retention = excluded.desired_retention,
             learning_steps = excluded.learning_steps,
             relearning_steps = excluded.relearning_steps",
    )
    .bind(payload.desired_retention)
    .bind(learning_json)
    .bind(relearning_json)
    .execute(&state.pool)
    .await?;

    Ok(Json(FsrsSettings {
        desired_retention: payload.desired_retention,
        learning_steps: payload.learning_steps,
        relearning_steps: payload.relearning_steps,
    }))
}

pub async fn get_fsrs_config(pool: &SqlitePool) -> AppResult<FsrsConfig> {
    let row = fetch_settings(pool).await?;
    let learning_steps = parse_steps_json(&row.learning_steps)?
        .into_iter()
        .map(|value| parse_step_duration(&value))
        .collect::<Result<Vec<i64>, _>>()?;
    let relearning_steps = parse_steps_json(&row.relearning_steps)?
        .into_iter()
        .map(|value| parse_step_duration(&value))
        .collect::<Result<Vec<i64>, _>>()?;

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
        "SELECT desired_retention, learning_steps, relearning_steps
         FROM fsrs_settings WHERE id = 1",
    )
    .fetch_optional(pool)
    .await?;

    if let Some(row) = row {
        return Ok(row);
    }

    let defaults = default_settings_row();
    sqlx::query(
        "INSERT INTO fsrs_settings (id, desired_retention, learning_steps, relearning_steps)
         VALUES (1, ?, ?, ?)",
    )
    .bind(defaults.desired_retention)
    .bind(defaults.learning_steps.clone())
    .bind(defaults.relearning_steps.clone())
    .execute(pool)
    .await?;

    Ok(defaults)
}

fn parse_steps_json(value: &str) -> AppResult<Vec<String>> {
    if let Ok(steps) = serde_json::from_str::<Vec<String>>(value) {
        if !steps.is_empty() {
            return Ok(steps);
        }
    }

    let steps = value
        .split(',')
        .map(|item| item.trim().trim_matches('"').to_string())
        .filter(|item| !item.is_empty())
        .collect::<Vec<_>>();

    if steps.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }

    Ok(steps)
}

fn validate_retention(retention: f64) -> AppResult<()> {
    if !(0.7..=0.97).contains(&retention) {
        return Err(StatusCode::BAD_REQUEST.into());
    }
    Ok(())
}

fn validate_steps(steps: &[String], field: &str) -> AppResult<()> {
    if steps.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }
    for step in steps {
        if parse_step_duration(step).is_err() {
            tracing::warn!(field = %field, step = %step, "Invalid FSRS step");
            return Err(StatusCode::BAD_REQUEST.into());
        }
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

fn parse_step_duration(value: &str) -> Result<i64, StatusCode> {
    if value.len() < 2 {
        return Err(StatusCode::BAD_REQUEST);
    }
    let (number, unit) = value.split_at(value.len() - 1);
    let amount = number.parse::<i64>().map_err(|_| StatusCode::BAD_REQUEST)?;
    if amount <= 0 {
        return Err(StatusCode::BAD_REQUEST);
    }
    let seconds = match unit {
        "s" => amount,
        "m" => amount * 60,
        "h" => amount * 60 * 60,
        "d" => amount * 60 * 60 * 24,
        _ => return Err(StatusCode::BAD_REQUEST),
    };
    Ok(seconds)
}

fn default_settings_row() -> FsrsSettingsRow {
    FsrsSettingsRow {
        desired_retention: DEFAULT_RETENTION,
        learning_steps: serde_json::to_string(&DEFAULT_LEARNING_STEPS)
            .unwrap_or_else(|_| "[\"1m\",\"10m\"]".to_string()),
        relearning_steps: serde_json::to_string(&DEFAULT_RELEARNING_STEPS)
            .unwrap_or_else(|_| "[\"10m\"]".to_string()),
    }
}
