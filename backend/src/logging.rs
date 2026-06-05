use crate::config::Config;
use axum::http::{Request, header::USER_AGENT};
use axum::middleware::Next;
use axum::response::Response;
use std::time::Instant;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::fmt::time::ChronoLocal;

pub fn init_logging(
    config: &Config,
    verbosity: u8,
) -> Option<tracing_appender::non_blocking::WorkerGuard> {
    let file_appender = tracing_appender::rolling::never(
        config
            .log_file
            .parent()
            .unwrap_or_else(|| std::path::Path::new(".")),
        config
            .log_file
            .file_name()
            .unwrap_or_else(|| std::ffi::OsStr::new("koun.log")),
    );
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        let level = match verbosity {
            0 => "info",
            1 => "debug",
            _ => "trace",
        };
        EnvFilter::new(format!("{level},tower_http={level}"))
    });

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_timer(ChronoLocal::rfc_3339())
        .compact()
        .with_writer(non_blocking)
        .init();

    Some(guard)
}

pub async fn access_log(req: Request<axum::body::Body>, next: Next) -> Response {
    let method = req.method().clone();
    let uri = req.uri().clone();
    let request_id = req
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("-")
        .to_string();
    let user_agent = req
        .headers()
        .get(USER_AGENT)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("-")
        .to_string();
    let start = Instant::now();
    let response = next.run(req).await;
    let status = response.status();
    let duration = start.elapsed().as_millis();
    tracing::info!(
        request_id = %request_id,
        method = %method,
        uri = %uri,
        status = %status,
        duration_ms = %duration,
        user_agent = %user_agent,
        "request"
    );
    response
}
