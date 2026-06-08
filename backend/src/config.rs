use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(author, version, about)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    #[command(flatten)]
    pub config: Config,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    HashPassword,
}

#[derive(Parser, Debug, Clone)]
pub struct Config {
    #[arg(long, env = "KOUN_BIND", default_value = "0.0.0.0:8080")]
    pub bind: String,

    #[arg(long, env = "KOUN_DB", default_value = "koun.sqlite")]
    pub database_path: String,

    #[arg(long, env = "KOUN_LOG_FILE", default_value = "koun.log")]
    pub log_file: PathBuf,

    #[arg(short, long, action = clap::ArgAction::Count, env = "KOUN_VERBOSE", default_value_t = 0)]
    pub verbose: u8,

    #[arg(long, env = "KOUN_CORS_ORIGIN")]
    pub cors_origin: Option<String>,

    #[arg(long, env = "KOUN_JWT_SECRET")]
    pub jwt_secret: Option<String>,

    #[arg(long, env = "KOUN_PASSWORD_HASH")]
    pub password_hash: Option<String>,

    #[arg(long, env = "KOUN_ELEVENLABS_API_KEY")]
    pub elevenlabs_api_key: Option<String>,

    #[arg(
        long,
        env = "KOUN_ELEVENLABS_VOICE_ID",
        default_value = "cgSgspJ2msm6clMCkdW9"
    )]
    pub elevenlabs_voice_id: String,

    #[arg(
        long,
        env = "KOUN_ELEVENLABS_MODEL_ID",
        default_value = "eleven_multilingual_v2"
    )]
    pub elevenlabs_model_id: String,

    #[arg(long, env = "KOUN_AUDIO_DIR", default_value = "card_audio")]
    pub audio_dir: PathBuf,
}

impl Config {
    #[must_use]
    pub fn log_filter(&self) -> &'static str {
        match self.verbose {
            0 => "info,koun=info,axum=info,tower_http=info",
            1 => "debug,koun=debug,axum=info,tower_http=info,sqlx=warn",
            _ => "trace,koun=trace,axum=trace,tower_http=trace,sqlx=debug",
        }
    }
}
