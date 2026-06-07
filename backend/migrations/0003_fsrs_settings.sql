CREATE TABLE fsrs_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    desired_retention REAL NOT NULL,
    learning_step_1_minutes INTEGER NOT NULL,
    learning_step_2_minutes INTEGER NOT NULL,
    relearning_step_minutes INTEGER NOT NULL
);

INSERT INTO fsrs_settings (id, desired_retention, learning_step_1_minutes, learning_step_2_minutes, relearning_step_minutes)
VALUES (1, 0.9, 1, 10, 10)
ON CONFLICT(id) DO NOTHING;

ALTER TABLE schedule_state ADD COLUMN fsrs_learning_step INTEGER NOT NULL DEFAULT 0;
ALTER TABLE schedule_state ADD COLUMN fsrs_relearning_step INTEGER NOT NULL DEFAULT 0;

