use crate::models::{ReviewRating, ScheduleState};

pub struct FsrsConfig {
    pub desired_retention: f64,
    pub learning_steps: Vec<i64>,
    pub relearning_steps: Vec<i64>,
}

pub fn fsrs_retrievability(stability: f64, last_review_at: i64, now: i64) -> f64 {
    if last_review_at == 0 {
        return 1.0;
    }
    let elapsed_days = ((now - last_review_at) as f64) / 86_400.0;
    let stability = stability.max(0.5);
    let decay = (0.9f64).ln() * (elapsed_days / stability);
    decay.exp().clamp(0.0, 1.0)
}

pub fn apply_fsrs(
    state: &mut ScheduleState,
    rating: ReviewRating,
    reviewed_at: i64,
    settings: &FsrsConfig,
) -> i64 {
    let is_new = state.fsrs_last_review_at == 0;
    let in_learning = state.fsrs_learning_step > 0 || is_new;

    update_fsrs_state(state, rating);
    state.fsrs_last_review_at = reviewed_at;

    if in_learning {
        return apply_learning_steps(state, rating, reviewed_at, settings);
    }

    if state.fsrs_relearning_step > 0 {
        return apply_relearning_steps(state, rating, reviewed_at, settings);
    }

    if rating == ReviewRating::Again {
        return start_relearning(state, reviewed_at, settings);
    }

    let due_at = due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
    state.fsrs_due_at = due_at;
    due_at
}

fn update_fsrs_state(state: &mut ScheduleState, rating: ReviewRating) {
    let mut stability = state.fsrs_stability.max(0.5);
    let mut difficulty = state.fsrs_difficulty;
    match rating {
        ReviewRating::Again => {
            stability *= 0.6;
            difficulty += 1.0;
        }
        ReviewRating::Hard => {
            stability *= 0.9;
            difficulty += 0.3;
        }
        ReviewRating::Good => {
            stability *= 1.2;
            difficulty -= 0.1;
        }
        ReviewRating::Easy => {
            stability *= 1.5;
            difficulty -= 0.3;
        }
    }

    state.fsrs_difficulty = difficulty.clamp(1.0, 10.0);
    state.fsrs_stability = stability.max(0.5);
}

fn apply_learning_steps(
    state: &mut ScheduleState,
    rating: ReviewRating,
    reviewed_at: i64,
    settings: &FsrsConfig,
) -> i64 {
    if settings.learning_steps.is_empty() {
        let due_at =
            due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
        state.fsrs_due_at = due_at;
        state.fsrs_learning_step = 0;
        return due_at;
    }

    let mut step = state.fsrs_learning_step.max(1) as usize;

    match rating {
        ReviewRating::Again => step = 1,
        ReviewRating::Hard => {}
        ReviewRating::Good | ReviewRating::Easy => step += 1,
    }

    if step > settings.learning_steps.len() {
        state.fsrs_learning_step = 0;
        let due_at =
            due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
        state.fsrs_due_at = due_at;
        return due_at;
    }

    state.fsrs_learning_step = step as i64;
    state.fsrs_relearning_step = 0;
    let due_at = reviewed_at + settings.learning_steps[step - 1];
    state.fsrs_due_at = due_at;
    due_at
}

fn start_relearning(
    state: &mut ScheduleState,
    reviewed_at: i64,
    settings: &FsrsConfig,
) -> i64 {
    if settings.relearning_steps.is_empty() {
        let due_at =
            due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
        state.fsrs_due_at = due_at;
        return due_at;
    }

    state.fsrs_relearning_step = 1;
    let due_at = reviewed_at + settings.relearning_steps[0];
    state.fsrs_due_at = due_at;
    due_at
}

fn apply_relearning_steps(
    state: &mut ScheduleState,
    rating: ReviewRating,
    reviewed_at: i64,
    settings: &FsrsConfig,
) -> i64 {
    if settings.relearning_steps.is_empty() {
        let due_at =
            due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
        state.fsrs_due_at = due_at;
        state.fsrs_relearning_step = 0;
        return due_at;
    }

    let mut step = state.fsrs_relearning_step.max(1) as usize;

    match rating {
        ReviewRating::Again => step = 1,
        ReviewRating::Hard => {}
        ReviewRating::Good | ReviewRating::Easy => step += 1,
    }

    if step > settings.relearning_steps.len() {
        state.fsrs_relearning_step = 0;
        let due_at =
            due_from_stability(state.fsrs_stability, reviewed_at, settings.desired_retention);
        state.fsrs_due_at = due_at;
        return due_at;
    }

    state.fsrs_relearning_step = step as i64;
    let due_at = reviewed_at + settings.relearning_steps[step - 1];
    state.fsrs_due_at = due_at;
    due_at
}

fn due_from_stability(stability: f64, reviewed_at: i64, desired_retention: f64) -> i64 {
    let stability_days = stability.max(0.5);
    let retention = desired_retention.clamp(0.7, 0.97);
    let interval_days = (retention.ln() / 0.9f64.ln()) * stability_days;
    let interval_days = interval_days.round().max(1.0) as i64;
    reviewed_at + interval_days * 86_400
}
