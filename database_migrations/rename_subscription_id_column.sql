-- Rename the id column to subscription_id in the subscriptions table
ALTER TABLE subscriptions RENAME COLUMN id TO subscription_id;

-- Rename the sequence
ALTER SEQUENCE subscriptions_id_seq RENAME TO subscriptions_subscription_id_seq;

-- Update the default value for the subscription_id column
ALTER TABLE subscriptions ALTER COLUMN subscription_id SET DEFAULT nextval('subscriptions_subscription_id_seq'::regclass);

-- Update any foreign key constraints that reference this column
-- Note: You'll need to manually update any foreign key constraints in other tables
-- that reference subscriptions.id to now reference subscriptions.subscription_id

-- Example of how to update a foreign key constraint (uncomment and modify as needed):
-- ALTER TABLE some_other_table 
-- DROP CONSTRAINT some_other_table_subscription_id_fkey,
-- ADD CONSTRAINT some_other_table_subscription_id_fkey 
-- FOREIGN KEY (subscription_id) REFERENCES subscriptions(subscription_id);
