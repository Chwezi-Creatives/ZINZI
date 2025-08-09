-- Add 'macos' as a valid platform in the fcm_tokens table
ALTER TABLE fcm_tokens 
DROP CONSTRAINT fcm_tokens_platform_check;

ALTER TABLE fcm_tokens
ADD CONSTRAINT fcm_tokens_platform_check 
CHECK (platform IN ('android', 'ios', 'web','windows','macos'));
