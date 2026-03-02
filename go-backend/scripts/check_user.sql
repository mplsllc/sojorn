-- Check a user's account status.
-- Usage: psql ... -f check_user.sql -v email='user@example.com'
SELECT id, email, status, deleted_at, encrypted_password FROM users WHERE email = :'email';
