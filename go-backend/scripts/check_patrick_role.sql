SELECT u.email, p.role FROM users u LEFT JOIN profiles p ON u.id = p.id WHERE u.email = 'admin@sojorn.net';
