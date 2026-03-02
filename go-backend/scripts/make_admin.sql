-- Grant admin role to a user by email.
-- Usage: psql ... -f make_admin.sql -v email='user@example.com'
UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = :'email');
