PRAGMA foreign_keys = ON;

ALTER TABLE card_directions ADD COLUMN new_cards_learned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_directions ADD COLUMN old_cards_reviewed INTEGER NOT NULL DEFAULT 0;

ALTER TABLE schedule_state ADD COLUMN new_cards_learned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE schedule_state ADD COLUMN old_cards_reviewed INTEGER NOT NULL DEFAULT 0;

UPDATE card_directions SET new_cards_learned = 0, old_cards_reviewed = 0;
UPDATE schedule_state SET new_cards_learned = 0, old_cards_reviewed = 0;

CREATE INDEX idx_card_directions_daily_counters ON card_directions(new_cards_learned, old_cards_reviewed);
CREATE INDEX idx_schedule_state_daily_counters ON schedule_state(new_cards_learned, old_cards_reviewed);