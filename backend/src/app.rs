use axum::extract::DefaultBodyLimit;
use axum::middleware::{from_fn, from_fn_with_state};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use serde::Serialize;
use tower::ServiceBuilder;
use tower_http::cors::{Any, CorsLayer};
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};

use crate::auth_middleware::require_auth;
use crate::config::Config;
use crate::embedded_web::serve_embedded_web;
use crate::logging::{access_log, log_payloads};
use crate::models::AppState;
use crate::routes::{auth, cards, reviews, settings, stats, translations};

async fn healthz() -> Json<&'static str> {
    Json("ok")
}

#[derive(Serialize)]
struct VersionInfo {
    version: &'static str,
}

async fn version() -> Json<VersionInfo> {
    Json(VersionInfo {
        version: env!("CARGO_PKG_VERSION"),
    })
}

fn cors_layer(config: &Config) -> CorsLayer {
    let cors = CorsLayer::new().allow_methods(Any).allow_headers(Any);
    if let Some(origin) = &config.cors_origin {
        cors.allow_origin(
            origin
                .parse::<axum::http::HeaderValue>()
                .expect("Invalid CORS origin"),
        )
    } else {
        cors.allow_origin(Any)
    }
}

pub fn build_app(state: AppState) -> Router {
    let request_id_layer = ServiceBuilder::new()
        .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
        .layer(PropagateRequestIdLayer::x_request_id());

    let public_routes = Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .route("/auth/login", post(auth::login))
        .route("/auth/refresh", post(auth::refresh));

    let protected_routes = Router::new()
        .route("/cards", get(cards::list_cards).post(cards::create_card))
        .route("/cards/from-english", post(cards::create_card_from_english))
        .route("/cards/{id}/audio", get(cards::get_card_audio))
        .route(
            "/cards/{id}",
            patch(cards::update_card).delete(cards::delete_card),
        )
        .route("/reviews/next", get(reviews::next_review))
        .route("/reviews/sync", post(reviews::sync_reviews))
        .route("/translate", post(translations::translate_text))
        .route("/stats/reviews-per-day", get(stats::reviews_per_day))
        .route(
            "/settings/fsrs",
            get(settings::get_fsrs_settings).put(settings::set_fsrs_settings),
        )
        .route_layer(from_fn_with_state(state.clone(), require_auth));

    Router::new()
        .merge(public_routes)
        .merge(protected_routes)
        .fallback(serve_embedded_web)
        .with_state(state.clone())
        .layer(DefaultBodyLimit::max(5 * 1024 * 1024))
        .layer(request_id_layer)
        .layer(from_fn(access_log))
        .layer(from_fn(log_payloads))
        .layer(cors_layer(&state.config))
}
