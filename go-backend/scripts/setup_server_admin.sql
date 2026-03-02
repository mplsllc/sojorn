-- Grant admin role and reset password for a user.
-- Usage: psql ... -f setup_server_admin.sql -v email='user@example.com' -v hash='$2a$10$...'
UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = :'email');
UPDATE users SET encrypted_password = :'hash' WHERE email = :'email';
