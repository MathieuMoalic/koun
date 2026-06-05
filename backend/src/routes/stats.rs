use axum::{Json, extract::State};
use sqlx::FromRow;

use crate::error::AppResult;
use crate::models::{AppState, ReviewsPerDay};

#[derive(FromRow)]
struct ReviewsPerDayRow {
    day: String,
    count: i64,
}

pub async fn reviews_per_day(State(state): State<AppState>) -> AppResult<Json<Vec<ReviewsPerDay>>> {
    let rows = sqlx::query_as::<_, ReviewsPerDayRow>(
        "SELECT strftime('%Y-%m-%d', reviewed_at, 'unixepoch') as day,
                COUNT(*) as count
         FROM reviews
         GROUP BY day
         ORDER BY day DESC
         LIMIT 90",
    )
    .fetch_all(&state.pool)
    .await?;

    let stats = rows
        .into_iter()
        .map(|row| ReviewsPerDay {
            day: row.day,
            count: row.count,
        })
        .collect();

    Ok(Json(stats))
}
