-- Create payment_transactions table if it doesn't exist
CREATE TABLE IF NOT EXISTS payment_transactions (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,
    external_id VARCHAR(100) UNIQUE NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    status VARCHAR(50) NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    payment_details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create disbursement_transactions table if it doesn't exist
CREATE TABLE IF NOT EXISTS disbursement_transactions (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,
    external_id VARCHAR(100) UNIQUE NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    status VARCHAR(50) NOT NULL,
    recipient_id VARCHAR(100) NOT NULL,
    recipient_type VARCHAR(50) NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_payment_transactions_external_id ON payment_transactions(external_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_created_at ON payment_transactions(created_at);

CREATE INDEX IF NOT EXISTS idx_disbursement_transactions_external_id ON disbursement_transactions(external_id);
CREATE INDEX IF NOT EXISTS idx_disbursement_transactions_recipient_id ON disbursement_transactions(recipient_id);
CREATE INDEX IF NOT EXISTS idx_disbursement_transactions_status ON disbursement_transactions(status);
CREATE INDEX IF NOT EXISTS idx_disbursement_transactions_created_at ON disbursement_transactions(created_at);

-- Add comments to tables and columns
COMMENT ON TABLE payment_transactions IS 'Stores MoMo payment transactions';
COMMENT ON COLUMN payment_transactions.transaction_id IS 'MoMo transaction ID';
COMMENT ON COLUMN payment_transactions.external_id IS 'External reference ID used by the application';
COMMENT ON COLUMN payment_transactions.payment_details IS 'JSON containing payment request details and MoMo response';

COMMENT ON TABLE disbursement_transactions IS 'Stores MoMo disbursement transactions';
COMMENT ON COLUMN disbursement_transactions.transaction_id IS 'MoMo transaction ID';
COMMENT ON COLUMN disbursement_transactions.external_id IS 'External reference ID used by the application';
COMMENT ON COLUMN disbursement_transactions.recipient_id IS 'Recipient''s ID (phone number or account number)';
COMMENT ON COLUMN disbursement_transactions.recipient_type IS 'Type of recipient ID (e.g., MSISDN for phone number)';
COMMENT ON COLUMN disbursement_transactions.details IS 'JSON containing disbursement details and MoMo response';
