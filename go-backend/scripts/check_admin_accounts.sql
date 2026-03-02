-- Check all admin-role accounts.
SELECT u.email, u.status, p.role, p.handle
FROM users u
LEFT JOIN profiles p ON u.id = p.id
WHERE p.role = 'admin'
ORDER BY u.email;
