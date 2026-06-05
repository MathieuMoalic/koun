CREATE TABLE fsrs_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    desired_retention REAL NOT NULL,
    learning_steps TEXT NOT NULL,
    relearning_steps TEXT NOT NULL
);

INSERT INTO fsrs_settings (id, desired_retention, learning_steps, relearning_steps)
VALUES (1, 0.9, '[\"1m\",\"10m\"]', '[\"10m\"]')
ON CONFLICT(id) DO NOTHING;

ALTER TABLE schedule_state ADD COLUMN fsrs_learning_step INTEGER NOT NULL DEFAULT 0;
ALTER TABLE schedule_state ADD COLUMN fsrs_relearning_step INTEGER NOT NULL DEFAULT 0;
