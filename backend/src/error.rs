use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use std::fmt;

#[derive(Debug)]
pub enum AppError {
    Status(StatusCode),
    Anyhow(anyhow::Error),
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::Status(status) => write!(f, "{status}"),
            AppError::Anyhow(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for AppError {}

impl From<StatusCode> for AppError {
    fn from(status: StatusCode) -> Self {
        Self::Status(status)
    }
}

impl From<anyhow::Error> for AppError {
    fn from(error: anyhow::Error) -> Self {
        Self::Anyhow(error)
    }
}

impl From<reqwest::Error> for AppError {
    fn from(error: reqwest::Error) -> Self {
        Self::Anyhow(error.into())
    }
}

impl From<sqlx::Error> for AppError {
    fn from(error: sqlx::Error) -> Self {
        Self::Anyhow(error.into())
    }
}

impl From<std::io::Error> for AppError {
    fn from(error: std::io::Error) -> Self {
        Self::Anyhow(error.into())
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        match self {
            AppError::Status(status) => status.into_response(),
            AppError::Anyhow(error) => {
                tracing::error!("{error:?}");
                StatusCode::INTERNAL_SERVER_ERROR.into_response()
            }
        }
    }
}

pub type AppResult<T> = Result<T, AppError>;
