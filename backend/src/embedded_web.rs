use axum::http::{HeaderMap, HeaderValue, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use mime_guess::from_path;
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "web_build"]
struct WebAssets;

pub async fn serve_embedded_web(uri: Uri) -> Response {
    let path = uri.path().trim_start_matches('/');
    let asset = WebAssets::get(path).or_else(|| WebAssets::get("index.html"));

    if let Some(asset) = asset {
        let mime = from_path(path).first_or_octet_stream();
        let mut headers = HeaderMap::new();
        headers.insert(
            axum::http::header::CONTENT_TYPE,
            HeaderValue::from_str(mime.as_ref())
                .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream")),
        );
        (headers, asset.data.into_owned()).into_response()
    } else {
        StatusCode::NOT_FOUND.into_response()
    }
}
