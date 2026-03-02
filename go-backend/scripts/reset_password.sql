-- Reset a user's password. Replace the email and use a strong password.
-- Usage: psql ... -f reset_password.sql -v email='user@example.com' -v newpass='new-strong-password'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE users SET encrypted_password = crypt(:'newpass', gen_salt('bf')) WHERE email = :'email';
