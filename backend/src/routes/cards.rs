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
use crate::routes::translations::{TranslationDirection, translate_text_payload};
use crate::scheduling::fsrs_retrievability;

#[derive(Deserialize)]
pub struct CreateCardReq {
    pub front: String,
    pub back: String,
    pub hint: Option<String>,
    pub card_type: Option<String>,
}

#[derive(Deserialize)]
pub struct CreateCardFromEnglishReq {
    pub english: String,
    pub hint: Option<String>,
    pub card_type: Option<String>,
}

#[derive(Deserialize)]
pub struct UpdateCardReq {
    pub front: Option<String>,
    pub back: Option<String>,
    pub hint: Option<String>,
    pub card_type: Option<String>,
    pub suspended: Option<bool>,
}

const CARD_TYPES: [&str; 4] = ["noun", "verb", "adjective", "phrase"];

pub async fn list_cards(State(state): State<AppState>) -> AppResult<Json<Vec<CardListItem>>> {
    #[derive(sqlx::FromRow)]
    struct CardListRow {
        id: i64,
        front: String,
        back: String,
        hint: Option<String>,
        card_type: String,
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
        "SELECT cards.id, cards.front, cards.back, cards.hint, cards.card_type, cards.audio_path, cards.suspended, cards.created_at, cards.updated_at,
                schedule_state.fsrs_stability, schedule_state.fsrs_difficulty,
                schedule_state.fsrs_due_at, schedule_state.fsrs_last_review_at
          FROM cards
         JOIN card_directions ON card_directions.card_id = cards.id AND card_directions.direction = 'pl_to_en'
         JOIN schedule_state ON schedule_state.card_direction_id = card_directions.id
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
            card_type: row.card_type,
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
    let card_type = normalize_card_type(req.card_type)?.unwrap_or_else(|| "noun".to_string());
    let card = sqlx::query_as::<_, Card>(
        "INSERT INTO cards (front, back, hint, card_type, suspended, created_at, updated_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)
         RETURNING id, front, back, hint, card_type, suspended, created_at, updated_at",
    )
    .bind(req.front)
    .bind(req.back)
    .bind(req.hint)
    .bind(card_type)
    .bind(now)
    .bind(now)
    .fetch_one(&state.pool)
    .await?;

    let pl_to_en_direction_id = ensure_card_directions(&state.pool, card.id, now).await?;
    insert_schedule_state(&state.pool, pl_to_en_direction_id, now, 5.0).await?;
    if let Err(err) = generate_card_audio(&state, card.id, &card.front, &card.card_type).await {
        tracing::warn!(card_id = card.id, error = %err, "Failed to generate ElevenLabs audio");
    }

    Ok(Json(card))
}

pub async fn create_card_from_english(
    State(state): State<AppState>,
    Json(req): Json<CreateCardFromEnglishReq>,
) -> AppResult<Json<Card>> {
    let english = req.english.trim();
    if english.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }

    let now = now_ts();
    let card_type = normalize_card_type(req.card_type)?.unwrap_or_else(|| "noun".to_string());
    let translated = translate_text_payload(
        &state,
        english,
        TranslationDirection::EnToPl,
        Some(&card_type),
    )
    .await?;

    let front = build_front_from_translation(&card_type, &translated)?;
    let back = translated
        .english
        .as_deref()
        .map(strip_english_demonstrative)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| english.to_string());

    let card = sqlx::query_as::<_, Card>(
        "INSERT INTO cards (front, back, hint, card_type, suspended, created_at, updated_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)
         RETURNING id, front, back, hint, card_type, suspended, created_at, updated_at",
    )
    .bind(front)
    .bind(back)
    .bind(req.hint)
    .bind(card_type)
    .bind(now)
    .bind(now)
    .fetch_one(&state.pool)
    .await?;

    let pl_to_en_direction_id = ensure_card_directions(&state.pool, card.id, now).await?;
    insert_schedule_state(&state.pool, pl_to_en_direction_id, now, 5.0).await?;
    if let Err(err) = generate_card_audio(&state, card.id, &card.front, &card.card_type).await {
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
        card_type: String,
        audio_path: Option<String>,
    }

    let row = sqlx::query_as::<_, AudioRow>(
        "SELECT front, card_type, audio_path FROM cards WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;
    let audio_path = row.audio_path.unwrap_or_else(|| format!("card-{id}.mp3"));
    let path = state.config.audio_dir.join(&audio_path);
    if !path.exists() {
        tracing::info!(card_id = id, "Regenerating missing audio");
        generate_card_audio(&state, id, &row.front, &row.card_type).await?;
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
        "SELECT id, front, back, hint, card_type, suspended, created_at, updated_at FROM cards WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(StatusCode::NOT_FOUND)?;

    let front = req.front.unwrap_or(existing.front);
    let back = req.back.unwrap_or(existing.back);
    let hint = req.hint.or(existing.hint);
    let card_type = normalize_card_type(req.card_type)?.unwrap_or(existing.card_type);
    let suspended = req.suspended.unwrap_or(existing.suspended);
    let now = now_ts();

    let updated = sqlx::query_as::<_, Card>(
        "UPDATE cards SET front = ?, back = ?, hint = ?, card_type = ?, suspended = ?, updated_at = ?
         WHERE id = ?
         RETURNING id, front, back, hint, card_type, suspended, created_at, updated_at",
    )
    .bind(front)
    .bind(back)
    .bind(hint)
    .bind(card_type)
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

async fn ensure_card_directions(pool: &SqlitePool, card_id: i64, now: i64) -> AppResult<i64> {
    let pl_to_en_direction_id: i64 = sqlx::query_scalar(
        "INSERT INTO card_directions (card_id, direction, enabled, created_at, updated_at)
         VALUES (?, 'pl_to_en', 1, ?, ?)
         ON CONFLICT(card_id, direction) DO UPDATE SET enabled = 1, updated_at = excluded.updated_at
         RETURNING id",
    )
    .bind(card_id)
    .bind(now)
    .bind(now)
    .fetch_one(pool)
    .await?;

    sqlx::query(
        "INSERT INTO card_directions (card_id, direction, enabled, created_at, updated_at)
         VALUES (?, 'en_to_pl', 0, ?, ?)
         ON CONFLICT(card_id, direction) DO NOTHING",
    )
    .bind(card_id)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;

    Ok(pl_to_en_direction_id)
}

async fn insert_schedule_state(
    pool: &SqlitePool,
    card_direction_id: i64,
    now: i64,
    initial_difficulty: f64,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO schedule_state (
            card_direction_id,
            fsrs_stability, fsrs_difficulty, fsrs_due_at, fsrs_last_review_at,
            fsrs_learning_step, fsrs_relearning_step, updated_at,
            new_cards_learned, old_cards_reviewed
          )
          VALUES (?, 1.0, ?, ?, 0, 0, 0, ?, 0, 0)
          ON CONFLICT(card_direction_id) DO NOTHING",
    )
    .bind(card_direction_id)
    .bind(initial_difficulty)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}

fn strip_english_demonstrative(value: &str) -> String {
    let trimmed = value.trim();
    trimmed
        .strip_prefix("this ")
        .or_else(|| trimmed.strip_prefix("This "))
        .unwrap_or(trimmed)
        .trim()
        .to_string()
}

fn build_front_from_translation(
    card_type: &str,
    translated: &crate::routes::translations::TranslateTextResp,
) -> AppResult<String> {
    let value = match card_type {
        "noun" => {
            let singular = translated.polish_singular.as_deref().unwrap_or("").trim();
            let plural = translated.polish_plural.as_deref().unwrap_or("").trim();
            if singular.is_empty() {
                return Err(StatusCode::BAD_GATEWAY.into());
            }
            if plural.is_empty() {
                singular.to_string()
            } else {
                format!("{singular} / {plural}")
            }
        }
        "adjective" => {
            let masculine = translated.polish_masculine.as_deref().unwrap_or("").trim();
            let feminine = translated.polish_feminine.as_deref().unwrap_or("").trim();
            let neuter = translated.polish_neuter.as_deref().unwrap_or("").trim();
            let joined = [masculine, feminine, neuter]
                .into_iter()
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join(" / ");
            if joined.is_empty() {
                return Err(StatusCode::BAD_GATEWAY.into());
            }
            joined
        }
        "verb" => {
            let imperfective = translated
                .polish_imperfective
                .as_deref()
                .unwrap_or("ø")
                .trim();
            let perfective = translated
                .polish_perfective
                .as_deref()
                .unwrap_or("ø")
                .trim();
            format!(
                "{} / {}",
                if imperfective.is_empty() {
                    "ø"
                } else {
                    imperfective
                },
                if perfective.is_empty() {
                    "ø"
                } else {
                    perfective
                }
            )
        }
        _ => translated.translation.trim().to_string(),
    };

    if value.is_empty() {
        return Err(StatusCode::BAD_GATEWAY.into());
    }
    Ok(value)
}

fn normalize_card_type(value: Option<String>) -> AppResult<Option<String>> {
    let Some(card_type) = value else {
        return Ok(None);
    };

    let normalized = card_type.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }
    if CARD_TYPES.contains(&normalized.as_str()) {
        return Ok(Some(normalized));
    }
    Err(StatusCode::BAD_REQUEST.into())
}

fn strip_singular_demonstrative(value: &str) -> String {
    let trimmed = value.trim();
    let lowercase = trimmed.to_ascii_lowercase();
    for prefix in ["ten ", "ta ", "to "] {
        if lowercase.starts_with(prefix) {
            return trimmed[prefix.len()..].trim().to_string();
        }
    }
    trimmed.to_string()
}

fn audio_text_for_card(front: &str, card_type: &str) -> String {
    match card_type {
        "noun" => {
            let singular = front
                .split(" / ")
                .next()
                .unwrap_or(front)
                .trim()
                .to_string();
            let normalized = strip_singular_demonstrative(&singular);
            if normalized.is_empty() {
                singular
            } else {
                normalized
            }
        }
        "adjective" => front
            .split(" / ")
            .next()
            .unwrap_or(front)
            .trim()
            .to_string(),
        _ => front.trim().to_string(),
    }
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
    speed: f32,
}

async fn generate_card_audio(
    state: &AppState,
    card_id: i64,
    front: &str,
    card_type: &str,
) -> AppResult<()> {
    let api_key = match state.config.elevenlabs_api_key.as_ref() {
        Some(api_key) => api_key,
        None => {
            tracing::info!(
                card_id,
                "Skipping ElevenLabs audio generation because API key is not set"
            );
            return Ok(());
        }
    };

    fs::create_dir_all(&state.config.audio_dir).await?;

    let audio_file = format!("card-{card_id}.mp3");
    let audio_path = state.config.audio_dir.join(&audio_file);
    let client = reqwest::Client::new();
    let audio_text = audio_text_for_card(front, card_type);
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
            text: &audio_text,
            model_id: &state.config.elevenlabs_model_id,
            language_code: "pl",
            voice_settings: ElevenLabsVoiceSettings {
                stability: 0.5,
                similarity_boost: 0.75,
                speed: 0.8,
            },
        })
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(
            anyhow::anyhow!("ElevenLabs TTS failed with status {}", response.status()).into(),
        );
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

#[cfg(test)]
mod tests {
    use super::audio_text_for_card;

    #[test]
    fn noun_audio_uses_singular_without_demonstrative() {
        assert_eq!(audio_text_for_card("ten dom / te domy", "noun"), "dom");
        assert_eq!(
            audio_text_for_card("ta książka / te książki", "noun"),
            "książka"
        );
        assert_eq!(
            audio_text_for_card("to dziecko / te dzieci", "noun"),
            "dziecko"
        );
    }

    #[test]
    fn adjective_audio_uses_only_masculine() {
        assert_eq!(
            audio_text_for_card("dobry / dobra / dobre", "adjective"),
            "dobry"
        );
    }
}
