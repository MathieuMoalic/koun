CREATE TABLE cards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    hint TEXT,
    suspended INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE schedule_state (
    card_id INTEGER PRIMARY KEY,
    sm2_ease REAL NOT NULL,
    sm2_interval_days INTEGER NOT NULL,
    sm2_repetitions INTEGER NOT NULL,
    sm2_due_at INTEGER NOT NULL,
    leitner_box INTEGER NOT NULL,
    leitner_due_at INTEGER NOT NULL,
    fsrs_stability REAL NOT NULL,
    fsrs_difficulty REAL NOT NULL,
    fsrs_due_at INTEGER NOT NULL,
    fsrs_last_review_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
);

CREATE TABLE reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id INTEGER NOT NULL,
    rating TEXT NOT NULL,
    algorithm TEXT NOT NULL,
    reviewed_at INTEGER NOT NULL,
    FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
);

CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
