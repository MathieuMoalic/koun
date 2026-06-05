use axum::http::Request;
use axum::middleware::Next;
use axum::response::Response;
use axum::{extract::State, http::StatusCode};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};

use crate::error::AppError;
use crate::models::{AppState, Claims, TokenType};

pub async fn require_auth(
    State(state): State<AppState>,
    req: Request<axum::body::Body>,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let jwt_secret = state
        .config
        .jwt_secret
        .as_ref()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
    let decoding_key = DecodingKey::from_secret(jwt_secret.as_bytes());

    let claims = decode::<Claims>(token, &decoding_key, &Validation::new(Algorithm::HS256))
        .map_err(|_| StatusCode::UNAUTHORIZED)?
        .claims;

    if claims.token_type != TokenType::Access {
        return Err(StatusCode::UNAUTHORIZED.into());
    }

    Ok(next.run(req).await)
}
