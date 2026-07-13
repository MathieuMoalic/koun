PRAGMA foreign_keys = ON;

ALTER TABLE fsrs_settings ADD COLUMN new_cards_per_day INTEGER NOT NULL DEFAULT 50;
ALTER TABLE fsrs_settings ADD COLUMN old_cards_per_day INTEGER NOT NULL DEFAULT 200;

UPDATE fsrs_settings SET new_cards_per_day = 50, old_cards_per_day = 200
WHERE new_cards_per_day IS NULL;