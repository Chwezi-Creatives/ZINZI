-- Create calories_history table
CREATE TABLE calories_history (
    user_id INT NOT NULL,
    calories DECIMAL(10, 2),
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, last_updated), -- Composite primary key
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Optional: Add an index for faster lookups by user_id
CREATE INDEX idx_calories_history_user_id ON calories_history (user_id);