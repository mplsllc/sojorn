INSERT INTO suggested_users (user_id, reason, score) VALUES 
('e40f6513-0aae-40b4-8644-3edb1fe6a4e0', 'popular', 100), 
('be03a13a-4067-4b2e-829c-811caac2b5fb', 'popular', 95), 
('f4f341e6-42eb-45ac-8ce1-44d49388016c', 'new_creator', 80) 
ON CONFLICT DO NOTHING;
