-- Check a user's role.
-- Usage: psql ... -f check_patrick_role.sql -v email='user@example.com'
SELECT u.email, p.role FROM users u LEFT JOIN profiles p ON u.id = p.id WHERE u.email = :'email';
