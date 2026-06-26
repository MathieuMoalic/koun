use serde::Serialize;
use serde_json::{Value as JsonValue, json};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct LlmClient {
    pub base: String,
    pub token: String,
    pub model: String,
}

impl LlmClient {
    #[must_use]
    pub fn new(base: String, token: String, model: String) -> Self {
        Self { base, token, model }
    }

    /// # Errors
    ///
    /// Returns an error if the request fails, the HTTP status is not success,
    /// or the response body does not contain valid JSON content.
    pub async fn chat_json(
        &self,
        http: &reqwest::Client,
        system: &str,
        user: &str,
        temperature: f32,
        timeout: Duration,
        max_tokens: Option<u32>,
    ) -> anyhow::Result<JsonValue> {
        #[derive(Serialize)]
        struct Message<'a> {
            role: &'a str,
            content: &'a str,
        }

        #[derive(Serialize)]
        struct Body<'a> {
            model: &'a str,
            messages: Vec<Message<'a>>,
            temperature: f32,
            #[serde(skip_serializing_if = "Option::is_none")]
            max_tokens: Option<u32>,
            response_format: JsonValue,
        }

        let url = format!("{}/chat/completions", self.base.trim_end_matches('/'));
        let body = Body {
            model: &self.model,
            messages: vec![
                Message {
                    role: "system",
                    content: system,
                },
                Message {
                    role: "user",
                    content: user,
                },
            ],
            temperature,
            max_tokens,
            response_format: json!({ "type": "json_object" }),
        };

        let mut request = http
            .post(url)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .timeout(timeout)
            .json(&body);

        if !self.token.trim().is_empty() {
            request = request.bearer_auth(&self.token);
        }

        let response = request.send().await?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();

        if !status.is_success() {
            anyhow::bail!("LLM HTTP {status}: {text}");
        }

        let envelope: JsonValue = serde_json::from_str(&text)?;
        let content = envelope
            .pointer("/choices/0/message/content")
            .and_then(|value| value.as_str())
            .ok_or_else(|| anyhow::anyhow!("LLM response missing content"))?;

        if let Ok(json) = serde_json::from_str::<JsonValue>(content) {
            return Ok(json);
        }

        anyhow::bail!(
            "LLM did not return valid JSON. Preview: {}",
            content.chars().take(500).collect::<String>()
        )
    }
}
