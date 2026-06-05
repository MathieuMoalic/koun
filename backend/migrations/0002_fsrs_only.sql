PRAGMA foreign_keys = OFF;

CREATE TABLE schedule_state_new (
    card_id INTEGER PRIMARY KEY,
    fsrs_stability REAL NOT NULL,
    fsrs_difficulty REAL NOT NULL,
    fsrs_due_at INTEGER NOT NULL,
    fsrs_last_review_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
);

INSERT INTO schedule_state_new (
    card_id,
    fsrs_stability,
    fsrs_difficulty,
    fsrs_due_at,
    fsrs_last_review_at,
    updated_at
)
SELECT
    card_id,
    fsrs_stability,
    fsrs_difficulty,
    fsrs_due_at,
    fsrs_last_review_at,
    updated_at
FROM schedule_state;

DROP TABLE schedule_state;
ALTER TABLE schedule_state_new RENAME TO schedule_state;

CREATE TABLE reviews_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id INTEGER NOT NULL,
    rating TEXT NOT NULL,
    reviewed_at INTEGER NOT NULL,
    FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
);

INSERT INTO reviews_new (id, card_id, rating, reviewed_at)
SELECT id, card_id, rating, reviewed_at FROM reviews;

DROP TABLE reviews;
ALTER TABLE reviews_new RENAME TO reviews;

DROP TABLE settings;

PRAGMA foreign_keys = ON;
