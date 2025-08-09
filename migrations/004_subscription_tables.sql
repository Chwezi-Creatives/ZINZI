-- Create subscription_plans table
CREATE TABLE IF NOT EXISTS subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    price_in_cents INTEGER NOT NULL,
    billing_cycle_days INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    features JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create user_subscriptions table
CREATE TABLE IF NOT EXISTS user_subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    plan_id INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL,  -- 'active', 'expired', 'cancelled', 'pending_payment'
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE,
    payment_transaction_id INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    cancelled_at TIMESTAMP WITH TIME ZONE,
    
    -- Constraints
    CONSTRAINT fk_user_subscriptions_plan 
        FOREIGN KEY (plan_id) 
        REFERENCES subscription_plans(id) 
        ON DELETE RESTRICT,
        
    CONSTRAINT fk_user_subscriptions_transaction
        FOREIGN KEY (payment_transaction_id)
        REFERENCES payment_transactions(id)
        ON DELETE SET NULL,
        
    CONSTRAINT valid_status 
        CHECK (status IN ('active', 'expired', 'cancelled', 'pending_payment')),
        
    CONSTRAINT valid_dates 
        CHECK (end_date IS NULL OR end_date > start_date)
);

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status ON user_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_end_date ON user_subscriptions(end_date);

-- Add comments to tables and columns
COMMENT ON TABLE subscription_plans IS 'Stores available subscription plans';
COMMENT ON COLUMN subscription_plans.name IS 'Name of the subscription plan (e.g., "Bi-Weekly", "Monthly")';
COMMENT ON COLUMN subscription_plans.price_in_cents IS 'Price in the smallest currency unit (e.g., cents for KSH)';
COMMENT ON COLUMN subscription_plans.billing_cycle_days IS 'Billing cycle length in days (e.g., 14 for bi-weekly, 30 for monthly)';

COMMENT ON TABLE user_subscriptions IS 'Stores user subscription information';
COMMENT ON COLUMN user_subscriptions.status IS 'Current status of the subscription';
COMMENT ON COLUMN user_subscriptions.start_date IS 'When the subscription period starts';
COMMENT ON COLUMN user_subscriptions.end_date IS 'When the subscription period ends (NULL for active subscriptions with no end date)';

-- Insert default subscription plans
INSERT INTO subscription_plans (name, description, price_in_cents, billing_cycle_days, features)
VALUES 
    ('Bi-Weekly', 'Bi-Weekly Subscription Plan', 120000, 14, '["Unlimited access to all meals", "Free delivery on all orders", "Exclusive member discounts"]'::jsonb),
    ('Monthly', 'Monthly Subscription Plan', 200000, 30, '["Unlimited access to all meals", "Free delivery on all orders", "Exclusive member discounts", "Priority customer support"]'::jsonb)
ON CONFLICT (name) DO NOTHING;
