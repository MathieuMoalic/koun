use axum::{Json, extract::State, http::StatusCode};
use jsonwebtoken::{Algorithm, DecodingKey, Header, Validation, decode, encode};
use password_hash::{PasswordHash, PasswordVerifier};
use serde::{Deserialize, Serialize};

use crate::error::AppResult;
use crate::models::{AppState, Claims, TokenType};

const ACCESS_TOKEN_EXPIRY_SECS: u64 = 15 * 60;
const REFRESH_TOKEN_EXPIRY_SECS: u64 = 30 * 24 * 3600;

#[derive(Deserialize)]
pub struct LoginReq {
    pub password: String,
}

#[derive(Serialize)]
pub struct LoginResp {
    pub token: String,
    pub refresh_token: String,
}

#[derive(Deserialize)]
pub struct RefreshReq {
    pub refresh_token: String,
}

#[derive(Serialize)]
pub struct RefreshResp {
    pub token: String,
}

fn now_ts() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system time is after Unix epoch")
        .as_secs()
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginReq>,
) -> AppResult<Json<LoginResp>> {
    let stored_hash = state
        .config
        .password_hash
        .as_ref()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    let parsed = PasswordHash::new(stored_hash).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if argon2::Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed)
        .is_err()
    {
        return Err(StatusCode::UNAUTHORIZED.into());
    }

    let now = now_ts();

    let access_token = encode(
        &Header::new(Algorithm::HS256),
        &Claims {
            sub: 1,
            exp: now + ACCESS_TOKEN_EXPIRY_SECS,
            token_type: TokenType::Access,
        },
        &state.jwt_encoding,
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let refresh_token = encode(
        &Header::new(Algorithm::HS256),
        &Claims {
            sub: 1,
            exp: now + REFRESH_TOKEN_EXPIRY_SECS,
            token_type: TokenType::Refresh,
        },
        &state.jwt_encoding,
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(LoginResp {
        token: access_token,
        refresh_token,
    }))
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshReq>,
) -> AppResult<Json<RefreshResp>> {
    let jwt_secret = state
        .config
        .jwt_secret
        .as_ref()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
    let decoding_key = DecodingKey::from_secret(jwt_secret.as_bytes());

    let claims = decode::<Claims>(
        &req.refresh_token,
        &decoding_key,
        &Validation::new(Algorithm::HS256),
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?
    .claims;

    if claims.token_type != TokenType::Refresh {
        return Err(StatusCode::UNAUTHORIZED.into());
    }

    let access_token = encode(
        &Header::new(Algorithm::HS256),
        &Claims {
            sub: claims.sub,
            exp: now_ts() + ACCESS_TOKEN_EXPIRY_SECS,
            token_type: TokenType::Access,
        },
        &state.jwt_encoding,
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(RefreshResp { token: access_token }))
}
