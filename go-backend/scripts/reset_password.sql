CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE users SET encrypted_password = crypt('password123', gen_salt('bf')) WHERE email = 'admin@sojorn.net';
UPDATE users SET encrypted_password = crypt('password123', gen_salt('bf')) WHERE email = 'admin@sojorn.net';
