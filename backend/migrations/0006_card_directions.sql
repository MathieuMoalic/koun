PRAGMA foreign_keys = OFF;

CREATE TABLE card_directions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK(direction IN ('pl_to_en', 'en_to_pl')),
    enabled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(card_id, direction)
);

INSERT INTO card_directions (card_id, direction, enabled, created_at, updated_at)
SELECT id, 'pl_to_en', 1, created_at, updated_at
FROM cards;

INSERT INTO card_directions (card_id, direction, enabled, created_at, updated_at)
SELECT id, 'en_to_pl', 0, created_at, updated_at
FROM cards;

CREATE TABLE schedule_state_new (
    card_direction_id INTEGER PRIMARY KEY REFERENCES card_directions(id) ON DELETE CASCADE,
    fsrs_stability REAL NOT NULL,
    fsrs_difficulty REAL NOT NULL,
    fsrs_due_at INTEGER NOT NULL,
    fsrs_last_review_at INTEGER NOT NULL,
    fsrs_learning_step INTEGER NOT NULL,
    fsrs_relearning_step INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

INSERT INTO schedule_state_new (
    card_direction_id,
    fsrs_stability,
    fsrs_difficulty,
    fsrs_due_at,
    fsrs_last_review_at,
    fsrs_learning_step,
    fsrs_relearning_step,
    updated_at
)
SELECT
    directions.id,
    schedule.fsrs_stability,
    schedule.fsrs_difficulty,
    schedule.fsrs_due_at,
    schedule.fsrs_last_review_at,
    schedule.fsrs_learning_step,
    schedule.fsrs_relearning_step,
    schedule.updated_at
FROM schedule_state AS schedule
JOIN card_directions AS directions
    ON directions.card_id = schedule.card_id
   AND directions.direction = 'pl_to_en';

DROP TABLE schedule_state;
ALTER TABLE schedule_state_new RENAME TO schedule_state;

CREATE TABLE reviews_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_direction_id INTEGER NOT NULL REFERENCES card_directions(id) ON DELETE CASCADE,
    rating TEXT NOT NULL,
    reviewed_at INTEGER NOT NULL
);

INSERT INTO reviews_new (id, card_direction_id, rating, reviewed_at)
SELECT
    reviews.id,
    directions.id,
    reviews.rating,
    reviews.reviewed_at
FROM reviews
JOIN card_directions AS directions
    ON directions.card_id = reviews.card_id
   AND directions.direction = 'pl_to_en';

DROP TABLE reviews;
ALTER TABLE reviews_new RENAME TO reviews;

CREATE INDEX idx_card_directions_card_id ON card_directions(card_id);
CREATE INDEX idx_schedule_state_due ON schedule_state(fsrs_due_at);
CREATE INDEX idx_reviews_card_direction_id ON reviews(card_direction_id);

PRAGMA foreign_keys = ON;
