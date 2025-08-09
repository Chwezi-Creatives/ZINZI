-- Add app_version column to fcm_tokens table
ALTER TABLE fcm_tokens
ADD COLUMN IF NOT EXISTS app_version VARCHAR(50);

-- Update the trigger function to handle the new column
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
