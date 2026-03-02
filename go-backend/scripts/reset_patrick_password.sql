-- Reset a user's password to a bcrypt hash.
-- Generate hash: htpasswd -bnBC 10 "" 'newpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
-- Usage: psql ... -f reset_patrick_password.sql -v email='user@example.com' -v hash='$2a$10$...'
UPDATE users SET encrypted_password = :'hash' WHERE email = :'email';
