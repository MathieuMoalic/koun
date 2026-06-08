use axum::{
    Json,
    body::Body,
    extract::{Path, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde::Serialize;
use sqlx::SqlitePool;
use tokio::fs;

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
        audio_path: Option<String>,
        suspended: bool,
        created_at: i64,
        updated_at: i64,
        fsrs_stability: f64,
        fsrs_difficulty: f64,
        fsrs_due_at: i64,
        fsrs_last_review_at: i64,
    }

    let rows = sqlx::query_as::<_, CardListRow>(
        "SELECT cards.id, cards.front, cards.back, cards.hint, cards.audio_path, cards.suspended, cards.created_at, cards.updated_at,
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
            audio_available: row.audio_path.is_some(),
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
    if let Err(err) = generate_card_audio(&state, card.id, &card.front).await {
        tracing::warn!(card_id = card.id, error = %err, "Failed to generate ElevenLabs audio");
    }

    Ok(Json(card))
}

pub async fn get_card_audio(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Response<Body>> {
    #[derive(sqlx::FromRow)]
    struct AudioRow {
        front: String,
        audio_path: Option<String>,
    }

    let row = sqlx::query_as::<_, AudioRow>("SELECT front, audio_path FROM cards WHERE id = ?")
        .bind(id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or(StatusCode::NOT_FOUND)?;
    let audio_path = row.audio_path.unwrap_or_else(|| format!("card-{id}.mp3"));
    let path = state.config.audio_dir.join(&audio_path);
    if !path.exists() {
        tracing::info!(card_id = id, "Regenerating missing audio");
        generate_card_audio(&state, id, &row.front).await?;
    }
    let bytes = fs::read(path).await.map_err(|_| StatusCode::NOT_FOUND)?;

    Ok((
        [
            (header::CONTENT_TYPE, "audio/mpeg"),
            (header::CACHE_CONTROL, "no-store"),
        ],
        Body::from(bytes),
    )
        .into_response())
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

#[derive(Serialize)]
struct ElevenLabsTtsRequest<'a> {
    text: &'a str,
    model_id: &'a str,
    language_code: &'a str,
    voice_settings: ElevenLabsVoiceSettings,
}

#[derive(Serialize)]
struct ElevenLabsVoiceSettings {
    stability: f32,
    similarity_boost: f32,
}

async fn generate_card_audio(state: &AppState, card_id: i64, text: &str) -> AppResult<()> {
    let api_key = match state.config.elevenlabs_api_key.as_ref() {
        Some(api_key) => api_key,
        None => {
            tracing::info!(card_id, "Skipping ElevenLabs audio generation because API key is not set");
            return Ok(());
        }
    };

    fs::create_dir_all(&state.config.audio_dir).await?;

    let audio_file = format!("card-{card_id}.mp3");
    let audio_path = state.config.audio_dir.join(&audio_file);
    let client = reqwest::Client::new();
    let url = format!(
        "https://api.elevenlabs.io/v1/text-to-speech/{}",
        state.config.elevenlabs_voice_id
    );
    let response = client
        .post(url)
        .header("xi-api-key", api_key)
        .header(header::ACCEPT, "audio/mpeg")
        .query(&[("output_format", "mp3_44100_128")])
        .json(&ElevenLabsTtsRequest {
            text,
            model_id: &state.config.elevenlabs_model_id,
            language_code: "pl",
            voice_settings: ElevenLabsVoiceSettings {
                stability: 0.5,
                similarity_boost: 0.75,
            },
        })
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(anyhow::anyhow!(
            "ElevenLabs TTS failed with status {}",
            response.status()
        )
        .into());
    }

    let bytes = response.bytes().await?;
    fs::write(&audio_path, bytes).await?;

    sqlx::query("UPDATE cards SET audio_path = ? WHERE id = ?")
        .bind(audio_file)
        .bind(card_id)
        .execute(&state.pool)
        .await?;

    Ok(())
}
