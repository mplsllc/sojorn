-- Grant admin role and optionally clone user to a secondary admin email.
-- Usage: psql ... -f setup_mp_admin.sql -v email='user@example.com' -v admin_email='admin@example.com'
UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = :'email');

-- Create secondary admin account if it doesn't exist (copies password hash from primary)
INSERT INTO users (id, email, encrypted_password, status, mfa_enabled, email_newsletter, email_contact, created_at, updated_at)
SELECT gen_random_uuid(), :'admin_email', encrypted_password, 'active', false, false, false, NOW(), NOW()
FROM users WHERE email = :'email' AND NOT EXISTS (SELECT 1 FROM users WHERE email = :'admin_email')
LIMIT 1;

-- Create profile for secondary admin if user was created
INSERT INTO profiles (id, handle, display_name, birth_month, birth_year, role)
SELECT id, 'admin', 'Admin User', 1, 1990, 'admin' FROM users WHERE email = :'admin_email' AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = (SELECT id FROM users WHERE email = :'admin_email'));
