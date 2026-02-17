INSERT INTO users (id, email, encrypted_password, status, mfa_enabled, email_newsletter, email_contact, created_at, updated_at) 
VALUES (gen_random_uuid(), 'admin@sojorn.net', 'BCRYPT_HASH_REDACTED', 'active', false, false, false, NOW(), NOW());

INSERT INTO profiles (id, handle, display_name, birth_month, birth_year)
SELECT id, 'admin', 'Admin User', 1, 1990 FROM users WHERE email = 'admin@sojorn.net';
