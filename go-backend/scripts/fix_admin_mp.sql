-- Update admin@mp.ls profile to use different handle
UPDATE profiles SET handle = 'admin_mp', display_name = 'Admin MP' WHERE id IN (SELECT id FROM users WHERE email = 'admin@mp.ls');
