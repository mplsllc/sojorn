-- Set admin@sojorn.net as admin on server and reset password
UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = 'admin@sojorn.net');

UPDATE users SET encrypted_password = 'BCRYPT_HASH_REDACTED' WHERE email = 'admin@sojorn.net';
