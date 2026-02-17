package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/lib/pq"
)

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Read and execute the seed file
	seedSQL := `
-- Comprehensive Groups Seeding
-- Seed 15 demo groups across all categories with realistic data

INSERT INTO groups (
    name, 
    description, 
    category, 
    is_private, 
    avatar_url, 
    banner_url, 
    created_by,
    member_count,
    post_count
) VALUES 
-- General Category
('Tech Innovators', 'Discussing the latest in technology, AI, and digital innovation. Share your projects and get feedback from fellow tech enthusiasts.', 'general', false, 'https://media.sojorn.net/tech-avatar.jpg', 'https://media.sojorn.net/tech-banner.jpg', 1, 245, 892),

('Creative Minds', 'A space for artists, designers, and creative professionals to share work, get inspiration, and collaborate on projects.', 'general', false, 'https://media.sojorn.net/creative-avatar.jpg', 'https://media.sojorn.net/creative-banner.jpg', 2, 189, 567),

-- Hobby Category  
('Photography Club', 'Share your best shots, get feedback, learn techniques, and discuss gear. All skill levels welcome!', 'hobby', false, 'https://media.sojorn.net/photo-avatar.jpg', 'https://media.sojorn.net/photo-banner.jpg', 3, 156, 423),

('Garden Enthusiasts', 'From balcony gardens to small farms. Share tips, show off your plants, and connect with fellow gardeners.', 'hobby', true, 'https://media.sojorn.net/garden-avatar.jpg', 'https://media.sojorn.net/garden-banner.jpg', 4, 78, 234),

('Home Cooking Masters', 'Share recipes, cooking techniques, and kitchen adventures. From beginners to gourmet chefs.', 'hobby', false, 'https://media.sojorn.net/cooking-avatar.jpg', 'https://media.sojorn.net/cooking-banner.jpg', 5, 312, 891),

-- Sports Category
('Runners United', 'Training tips, race experiences, and running routes. Connect with runners of all levels in your area.', 'sports', false, 'https://media.sojorn.net/running-avatar.jpg', 'https://media.sojorn.net/running-banner.jpg', 6, 423, 1256),

('Yoga & Wellness', 'Daily practice sharing, meditation techniques, and wellness discussions. All levels welcome.', 'sports', false, 'https://media.sojorn.net/yoga-avatar.jpg', 'https://media.sojorn.net/yoga-banner.jpg', 7, 267, 789),

('Cycling Community', 'Road cycling, mountain biking, and urban cycling. Share routes, gear reviews, and group ride info.', 'sports', true, 'https://media.sojorn.net/cycling-avatar.jpg', 'https://media.sojorn.net/cycling-banner.jpg', 8, 198, 567),

-- Professional Category
('Startup Founders', 'Connect with fellow entrepreneurs, share experiences, and discuss the challenges of building companies.', 'professional', true, 'https://media.sojorn.net/startup-avatar.jpg', 'https://media.sojorn.net/startup-banner.jpg', 9, 134, 445),

('Remote Work Professionals', 'Tips, tools, and discussions about working remotely. Share your home office setup and productivity hacks.', 'professional', false, 'https://media.sojorn.net/remote-avatar.jpg', 'https://media.sojorn.net/remote-banner.jpg', 10, 523, 1567),

('Software Developers', 'Code reviews, tech discussions, career advice, and programming language debates. All languages welcome.', 'professional', false, 'https://media.sojorn.net/dev-avatar.jpg', 'https://media.sojorn.net/dev-banner.jpg', 11, 678, 2341),

-- Local Business Category
('Local Coffee Shops', 'Supporting local cafés and coffee culture. Share your favorite spots, reviews, and coffee experiences.', 'local_business', false, 'https://media.sojorn.net/coffee-avatar.jpg', 'https://media.sojorn.net/coffee-banner.jpg', 12, 89, 267),

('Farmers Market Fans', 'Celebrating local farmers markets, farm-to-table eating, and supporting local agriculture.', 'local_business', false, 'https://media.sojorn.net/market-avatar.jpg', 'https://media.sojorn.net/market-banner.jpg', 13, 156, 445),

-- Support Category
('Mental Health Support', 'A safe space to discuss mental health, share coping strategies, and find support. Confidential and respectful.', 'support', true, 'https://media.sojorn.net/mental-avatar.jpg', 'https://media.sojorn.net/mental-banner.jpg', 14, 234, 678),

('Parenting Community', 'Share parenting experiences, get advice, and connect with other parents. All parenting stages welcome.', 'support', false, 'https://media.sojorn.net/parenting-avatar.jpg', 'https://media.sojorn.net/parenting-banner.jpg', 15, 445, 1234),

-- Education Category
('Language Learning Exchange', 'Practice languages, find study partners, and share learning resources. All languages and levels.', 'education', false, 'https://media.sojorn.net/language-avatar.jpg', 'https://media.sojorn.net/language-banner.jpg', 16, 312, 923),

('Book Club Central', 'Monthly book discussions, recommendations, and literary analysis. From classics to contemporary fiction.', 'education', true, 'https://media.sojorn.net/books-avatar.jpg', 'https://media.sojorn.net/books-banner.jpg', 17, 178, 534);
`

	_, err = db.Exec(seedSQL)
	if err != nil {
		log.Printf("Error seeding groups: %v", err)
		return
	}

	fmt.Println("✅ Successfully seeded 15 demo groups across all categories")

	// Add sample members
	memberSQL := `
INSERT INTO group_members (group_id, user_id, role, joined_at)
SELECT 
    g.id,
    (random() * 100 + 1)::integer as user_id,
    CASE 
        WHEN random() < 0.05 THEN 'owner'
        WHEN random() < 0.15 THEN 'admin' 
        WHEN random() < 0.35 THEN 'moderator'
        ELSE 'member'
    END as role,
    NOW() - (random() * INTERVAL '365 days') as joined_at
FROM groups g
CROSS JOIN generate_series(1, g.member_count) 
WHERE g.member_count > 0;
`

	_, err = db.Exec(memberSQL)
	if err != nil {
		log.Printf("Error adding group members: %v", err)
		return
	}

	fmt.Println("✅ Successfully added group members")

	// Add sample posts
	postSQL := `
INSERT INTO posts (user_id, body, category, created_at, group_id)
SELECT 
    gm.user_id,
    CASE 
        WHEN random() < 0.3 THEN 'Just discovered this amazing group! Looking forward to connecting with everyone here. #excited'
        WHEN random() < 0.6 THEN 'Great discussion happening in this community. What are your thoughts on the latest developments?'
        ELSE 'Sharing something interesting I found today. Hope this sparks some good conversations!'
    END as body,
    'general',
    NOW() - (random() * INTERVAL '90 days') as created_at,
    gm.group_id
FROM group_members gm
WHERE gm.role != 'owner'
LIMIT 1000;
`

	_, err = db.Exec(postSQL)
	if err != nil {
		log.Printf("Error adding sample posts: %v", err)
		return
	}

	fmt.Println("✅ Successfully added sample posts")

	// Update post counts
	updateSQL := `
UPDATE groups g 
SET post_count = (
    SELECT COUNT(*) 
    FROM posts p 
    WHERE p.group_id = g.id
);
`

	_, err = db.Exec(updateSQL)
	if err != nil {
		log.Printf("Error updating post counts: %v", err)
		return
	}

	fmt.Println("✅ Successfully updated post counts")
	fmt.Println("🎉 Groups seeding completed successfully!")
}
