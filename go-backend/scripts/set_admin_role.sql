UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email = 'admin@sojorn.net');
