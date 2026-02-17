SELECT u.email, u.status, p.role, p.handle 
FROM users u 
LEFT JOIN profiles p ON u.id = p.id 
WHERE u.email IN ('admin@sojorn.net', 'admin@mp.ls', 'admin@sojorn.net') 
ORDER BY u.email;
