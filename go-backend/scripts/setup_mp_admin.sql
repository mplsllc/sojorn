-- Set admin@sojorn.net as admin
UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = 'admin@sojorn.net');

-- Create admin@mp.ls if it doesn't exist
INSERT INTO users (id, email, encrypted_password, status, mfa_enabled, email_newsletter, email_contact, created_at, updated_at) 
SELECT gen_random_uuid(), 'admin@mp.ls', encrypted_password, 'active', false, false, false, NOW(), NOW()
FROM users WHERE email = 'admin@sojorn.net' AND NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@mp.ls')
LIMIT 1;

-- Create profile for admin@mp.ls if user was created
INSERT INTO profiles (id, handle, display_name, birth_month, birth_year, role)
SELECT id, 'admin', 'Admin User', 1, 1990, 'admin' FROM users WHERE email = 'admin@mp.ls' AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = (SELECT id FROM users WHERE email = 'admin@mp.ls'));
