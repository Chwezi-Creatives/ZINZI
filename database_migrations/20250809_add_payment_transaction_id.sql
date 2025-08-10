-- Add payment_transaction_id column to subscriptions table
-- This makes the payment transaction ID optional for subscriptions

ALTER TABLE subscriptions 
ADD COLUMN IF NOT EXISTS payment_transaction_id TEXT NULL;

-- Add a comment to document the column
COMMENT ON COLUMN subscriptions.payment_transaction_id IS 'Optional reference to the payment transaction for this subscription';

-- Create an index for faster lookups by payment transaction ID
CREATE INDEX IF NOT EXISTS idx_subscriptions_payment_transaction_id 
ON subscriptions(payment_transaction_id) 
WHERE payment_transaction_id IS NOT NULL;
