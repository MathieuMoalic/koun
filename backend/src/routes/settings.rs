use axum::{Json, extract::State};
use sqlx::SqlitePool;

use crate::error::AppResult;
use crate::models::{Algorithm, AlgorithmSetting, AppState};

pub async fn get_algorithm(pool: &SqlitePool) -> AppResult<Algorithm> {
    let value: Option<String> = sqlx::query_scalar(
        "SELECT value FROM settings WHERE key = 'algorithm' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    Ok(value
        .as_deref()
        .and_then(parse_algorithm)
        .unwrap_or(Algorithm::Sm2))
}

pub async fn get_algorithm_setting(
    State(state): State<AppState>,
) -> AppResult<Json<AlgorithmSetting>> {
    let algorithm = get_algorithm(&state.pool).await?;
    Ok(Json(AlgorithmSetting { algorithm }))
}

pub async fn set_algorithm_setting(
    State(state): State<AppState>,
    Json(setting): Json<AlgorithmSetting>,
) -> AppResult<Json<AlgorithmSetting>> {
    let value = algorithm_to_str(setting.algorithm);
    sqlx::query(
        "INSERT INTO settings (key, value)
         VALUES ('algorithm', ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
    )
    .bind(value)
    .execute(&state.pool)
    .await?;
    Ok(Json(setting))
}

fn parse_algorithm(value: &str) -> Option<Algorithm> {
    match value {
        "sm2" => Some(Algorithm::Sm2),
        "fsrs" => Some(Algorithm::Fsrs),
        "leitner" => Some(Algorithm::Leitner),
        _ => None,
    }
}

fn algorithm_to_str(algorithm: Algorithm) -> &'static str {
    match algorithm {
        Algorithm::Sm2 => "sm2",
        Algorithm::Fsrs => "fsrs",
        Algorithm::Leitner => "leitner",
    }
}
