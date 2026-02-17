UPDATE profiles SET role = 'admin' WHERE id IN (SELECT id FROM users WHERE email IN ('admin@sojorn.net', 'admin@sojorn.net'));
