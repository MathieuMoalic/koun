use axum::{
    body::Body,
    http::{HeaderValue, Response, StatusCode, Uri, header},
    response::IntoResponse,
};
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "web_build"]
struct WebAssets;

pub async fn serve_embedded_web(uri: Uri) -> impl IntoResponse {
    let path = uri.path().trim_start_matches('/');

    // Try exact path first.
    if let Some(content) = WebAssets::get(path) {
        return serve_asset(path, content.data.into_owned());
    }

    // For SPA routing and `/`, serve index.html.
    if !path.contains('.') {
        if let Some(content) = WebAssets::get("index.html") {
            return serve_asset("index.html", content.data.into_owned());
        }
    }

    // Final fallback to index.html, matching the current koun behavior.
    if let Some(content) = WebAssets::get("index.html") {
        return serve_asset("index.html", content.data.into_owned());
    }

    StatusCode::NOT_FOUND.into_response()
}

fn serve_asset(path: &str, content: Vec<u8>) -> Response<Body> {
    let mime = mime_guess::from_path(path)
        .first_or_octet_stream()
        .to_string();

    Response::builder()
        .status(StatusCode::OK)
        .header(
            header::CONTENT_TYPE,
            HeaderValue::from_str(&mime)
                .unwrap_or(HeaderValue::from_static("application/octet-stream")),
        )
        .body(Body::from(content))
        .expect("valid response with known status and header")
}
