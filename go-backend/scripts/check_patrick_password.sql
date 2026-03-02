-- Check a user's password hash.
-- Usage: psql ... -f check_patrick_password.sql -v email='user@example.com'
SELECT email, encrypted_password FROM users WHERE email = :'email';
