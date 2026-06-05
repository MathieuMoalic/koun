use crate::config::Config;
use axum::http::Request;
use axum::middleware::Next;
use axum::response::Response;
use std::time::Instant;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::fmt::time::ChronoLocal;

pub fn init_logging(config: &Config) -> Option<tracing_appender::non_blocking::WorkerGuard> {
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

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,tower_http=info"));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_timer(ChronoLocal::rfc_3339())
        .with_writer(non_blocking)
        .init();

    Some(guard)
}

pub async fn access_log(req: Request<axum::body::Body>, next: Next) -> Response {
    let method = req.method().clone();
    let uri = req.uri().clone();
    let start = Instant::now();
    let response = next.run(req).await;
    let status = response.status();
    let duration = start.elapsed().as_millis();
    tracing::info!("{method} {uri} -> {status} ({duration}ms)");
    response
}
