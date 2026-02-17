-- Create profile for admin@mp.ls with unique handle
INSERT INTO profiles (id, handle, display_name, birth_month, birth_year, role)
SELECT id, 'admin_mp', 'Admin MP', 1, 1990, 'admin' FROM users WHERE email = 'admin@mp.ls' AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = (SELECT id FROM users WHERE email = 'admin@mp.ls'));
