use crate::models::{ReviewRating, ScheduleState};

pub fn apply_sm2(state: &mut ScheduleState, rating: ReviewRating, reviewed_at: i64) -> i64 {
    let quality = match rating {
        ReviewRating::Again => 0,
        ReviewRating::Hard => 3,
        ReviewRating::Good => 4,
        ReviewRating::Easy => 5,
    } as f64;

    if quality < 3.0 {
        state.sm2_repetitions = 0;
        state.sm2_interval_days = 1;
    } else {
        if state.sm2_repetitions == 0 {
            state.sm2_interval_days = 1;
        } else if state.sm2_repetitions == 1 {
            state.sm2_interval_days = 6;
        } else {
            let next_interval =
                (state.sm2_interval_days as f64 * state.sm2_ease).round().max(1.0);
            state.sm2_interval_days = next_interval as i64;
        }
        state.sm2_repetitions += 1;
    }

    let diff = 5.0 - quality;
    let new_ease = state.sm2_ease + (0.1 - diff * (0.08 + diff * 0.02));
    state.sm2_ease = new_ease.max(1.3);

    let due_at = reviewed_at + state.sm2_interval_days * 86_400;
    state.sm2_due_at = due_at;
    due_at
}

pub fn apply_leitner(state: &mut ScheduleState, rating: ReviewRating, reviewed_at: i64) -> i64 {
    let mut next_box = state.leitner_box;
    match rating {
        ReviewRating::Again => next_box = 1,
        ReviewRating::Hard => next_box = (next_box - 1).max(1),
        ReviewRating::Good => next_box = (next_box + 1).min(5),
        ReviewRating::Easy => next_box = (next_box + 2).min(5),
    }
    state.leitner_box = next_box;
    let interval_days = match next_box {
        1 => 1,
        2 => 2,
        3 => 4,
        4 => 8,
        _ => 16,
    };
    let due_at = reviewed_at + interval_days * 86_400;
    state.leitner_due_at = due_at;
    due_at
}

pub fn apply_fsrs(state: &mut ScheduleState, rating: ReviewRating, reviewed_at: i64) -> i64 {
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

    difficulty = difficulty.clamp(1.0, 10.0);
    stability = stability.max(0.5);

    let interval_days = stability.round().max(1.0) as i64;
    let due_at = reviewed_at + interval_days * 86_400;

    state.fsrs_stability = stability;
    state.fsrs_difficulty = difficulty;
    state.fsrs_due_at = due_at;
    state.fsrs_last_review_at = reviewed_at;
    due_at
}
