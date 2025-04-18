use koun::app;
use sqlx::sqlite::SqlitePoolOptions;
use tokio::signal;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::debug!("App starting...");

    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect("sqlite:./db.sqlite")
        .await?;

    sqlx::migrate!().run(&db).await?;

    let app = app(db);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            if let Err(e) = signal::ctrl_c().await {
                tracing::error!("Failed to listen for Ctrl+C: {}", e);
            }
            tracing::info!("Shutdown signal received.")
        })
        .await?;

    Ok(())
}
