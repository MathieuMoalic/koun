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

    #[arg(long, env = "KOUN_CORS_ORIGIN")]
    pub cors_origin: Option<String>,

    #[arg(long, env = "KOUN_JWT_SECRET")]
    pub jwt_secret: Option<String>,

    #[arg(long, env = "KOUN_PASSWORD_HASH")]
    pub password_hash: Option<String>,
}
