use crate::config::Config;
use chrono::Utc;
use jsonwebtoken::EncodingKey;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use sqlx::SqlitePool;

#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    pub jwt_encoding: EncodingKey,
    pub config: Config,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum ReviewRating {
    Again,
    Hard,
    Good,
    Easy,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub enum ReviewDirection {
    PlToEn,
    EnToPl,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum TokenType {
    Access,
    Refresh,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: i64,
    pub exp: u64,
    pub token_type: TokenType,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Card {
    pub id: i64,
    pub front: String,
    pub back: String,
    pub hint: Option<String>,
    pub card_type: String,
    pub suspended: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewItem {
    pub card_id: i64,
    pub card_direction_id: i64,
    pub direction: ReviewDirection,
    pub prompt: String,
    pub answer: String,
    pub hint: Option<String>,
    pub card_type: String,
    pub due_at: i64,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct CardListItem {
    pub id: i64,
    pub front: String,
    pub back: String,
    pub hint: Option<String>,
    pub card_type: String,
    pub audio_available: bool,
    pub suspended: bool,
    pub created_at: i64,
    pub updated_at: i64,
    pub fsrs_stability: f64,
    pub fsrs_difficulty: f64,
    pub fsrs_due_at: i64,
    pub fsrs_last_review_at: i64,
    pub fsrs_retrievability: f64,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct ScheduleState {
    pub card_direction_id: i64,
    pub fsrs_stability: f64,
    pub fsrs_difficulty: f64,
    pub fsrs_due_at: i64,
    pub fsrs_last_review_at: i64,
    pub fsrs_learning_step: i64,
    pub fsrs_relearning_step: i64,
    pub updated_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FsrsSettings {
    pub desired_retention: f64,
    pub learning_step_1_minutes: i64,
    pub learning_step_2_minutes: i64,
    pub relearning_step_minutes: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewEvent {
    pub card_direction_id: Option<i64>,
    #[serde(default)]
    pub card_id: Option<i64>,
    pub rating: ReviewRating,
    pub reviewed_at: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewSyncRequest {
    pub events: Vec<ReviewEvent>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewSyncResponse {
    pub processed: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewsPerDay {
    pub day: String,
    pub count: i64,
}

pub fn now_ts() -> i64 {
    Utc::now().timestamp()
}
