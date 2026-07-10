use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};

use crate::error::AppResult;
use crate::llm::LlmClient;
use crate::models::AppState;

#[derive(Deserialize, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub enum TranslationDirection {
    PlToEn,
    EnToPl,
}

#[derive(Deserialize)]
pub struct TranslateTextReq {
    pub text: String,
    pub direction: TranslationDirection,
    pub card_type: Option<String>,
}

#[derive(Serialize)]
pub struct TranslateTextResp {
    pub translation: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_singular: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_plural: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub english: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_masculine: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_feminine: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_neuter: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_imperfective: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub polish_perfective: Option<String>,
}

pub async fn translate_text_payload(
    state: &AppState,
    text: &str,
    direction: TranslationDirection,
    card_type: Option<&str>,
) -> AppResult<TranslateTextResp> {
    if text.is_empty() {
        return Err(StatusCode::BAD_REQUEST.into());
    }

    let Some(api_key) = state.config.llm_api_key.clone() else {
        tracing::warn!("Translation requested but KOUN_LLM_API_KEY is not set");
        return Err(StatusCode::BAD_REQUEST.into());
    };

    let direction_label = match direction {
        TranslationDirection::PlToEn => "Polish to English",
        TranslationDirection::EnToPl => "English to Polish",
    };

    let is_noun = card_type.is_some_and(|value| value.eq_ignore_ascii_case("noun"));
    let is_adjective = card_type.is_some_and(|value| value.eq_ignore_ascii_case("adjective"));
    let is_verb = card_type.is_some_and(|value| value.eq_ignore_ascii_case("verb"));

    let (system, user, max_tokens) = if is_noun {
        (
            "You are a Polish-English noun card generator. Return only strict JSON with keys: translation, polish_singular, polish_plural, english. No commentary, markdown, or extra keys. polish_singular must be exactly one Polish noun phrase with the correct singular demonstrative article: ten, ta, or to. polish_plural must be exactly one Polish plural noun phrase. For masculine-personal nouns (groups with at least one male person), use 'Ci' (e.g., mężczyźni→mężowie, studenci→studentów, rodzice→rodziców). For all other nouns (women-only, animals, objects, abstract concepts), use 'te' (e.g., kobiety→kobiet, koty→kotów, książki→książek, idea→idej). english must be the base English noun only, with no article, no 'this', and no plural unless the noun is plural-only. translation must match the requested direction: English only for Polish to English, Polish singular only for English to Polish.",
            format!("Direction: {direction_label}\nNoun text: {text}"),
            Some(192),
        )
    } else if is_adjective {
        (
            "You are a Polish-English adjective card generator. Return only strict JSON with keys: translation, polish_masculine, polish_feminine, polish_neuter, english. No commentary, markdown, or extra keys. polish_masculine must be the Polish masculine singular adjective form, polish_feminine the feminine singular form, and polish_neuter the neuter singular form. english must be the base English adjective only, with no article and no 'this'. translation must match the requested direction: English only for Polish to English, and the three Polish forms joined as masculine/feminine/neuter with slashes for English to Polish, for example dobry/dobra/dobre.",
            format!("Direction: {direction_label}\nAdjective text: {text}"),
            Some(192),
        )
    } else if is_verb {
        (
            "You are a Polish-English verb card generator. Return only strict JSON with keys: translation, polish_imperfective, polish_perfective, english. No commentary, markdown, or extra keys. polish_imperfective must be the Polish imperfective infinitive, polish_perfective must be the Polish perfective infinitive. If a natural aspect pair is missing or not normally used, set that missing Polish form to exactly ø. english must be the base English verb phrase only, with no 'to' unless it is part of a phrasal verb. translation must match the requested direction: English only for Polish to English, and the two Polish forms joined as imperfective/perfective with slashes for English to Polish, for example czytać/przeczytać or ø/spotkać.",
            format!("Direction: {direction_label}\nVerb text: {text}"),
            Some(192),
        )
    } else {
        (
            "You are a translation engine. Translate the user's text exactly once and return only strict JSON with a single key: {\"translation\":\"...\"}. Do not add commentary, markdown, or extra keys.",
            format!("Direction: {direction_label}\nText: {text}"),
            Some(128),
        )
    };

    let client = LlmClient::new(
        state.config.llm_api_url.clone(),
        api_key,
        state.config.llm_model.clone(),
    );
    let http = reqwest::Client::new();
    let response = client
        .chat_json(
            &http,
            system,
            &user,
            0.1,
            std::time::Duration::from_secs(30),
            max_tokens,
        )
        .await?;

    let translation = response
        .get("translation")
        .and_then(|value| value.as_str())
        .ok_or(StatusCode::BAD_GATEWAY)?
        .trim()
        .to_string();

    Ok(TranslateTextResp {
        translation,
        polish_singular: response
            .get("polish_singular")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_plural: response
            .get("polish_plural")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        english: response
            .get("english")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_masculine: response
            .get("polish_masculine")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_feminine: response
            .get("polish_feminine")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_neuter: response
            .get("polish_neuter")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_imperfective: response
            .get("polish_imperfective")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        polish_perfective: response
            .get("polish_perfective")
            .and_then(|value| value.as_str())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
    })
}

pub async fn translate_text(
    State(state): State<AppState>,
    Json(req): Json<TranslateTextReq>,
) -> AppResult<Json<TranslateTextResp>> {
    let text = req.text.trim();
    let response =
        translate_text_payload(&state, text, req.direction, req.card_type.as_deref()).await?;
    Ok(Json(response))
}
