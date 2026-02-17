-- Reset password for admin@sojorn.net to password123
UPDATE users SET encrypted_password = 'BCRYPT_HASH_REDACTED' WHERE email = 'admin@sojorn.net';
