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

	// Clear existing groups to start fresh
	_, err = db.Exec("DELETE FROM groups")
	if err != nil {
		log.Printf("Error clearing groups: %v", err)
		return
	}

	// Seed groups with correct column names
	seedSQL := `
INSERT INTO groups (
    name, 
    description, 
    category, 
    privacy, 
    avatar_url, 
    created_by,
    member_count,
    is_active
) VALUES 
-- General Category
('Tech Innovators', 'Discussing the latest in technology, AI, and digital innovation. Share your projects and get feedback from fellow tech enthusiasts.', 'general', 'public', 'https://media.sojorn.net/tech-avatar.jpg', 1, 245, true),

('Creative Minds', 'A space for artists, designers, and creative professionals to share work, get inspiration, and collaborate on projects.', 'general', 'public', 'https://media.sojorn.net/creative-avatar.jpg', 2, 189, true),

-- Hobby Category  
('Photography Club', 'Share your best shots, get feedback, learn techniques, and discuss gear. All skill levels welcome!', 'hobby', 'public', 'https://media.sojorn.net/photo-avatar.jpg', 3, 156, true),

('Garden Enthusiasts', 'From balcony gardens to small farms. Share tips, show off your plants, and connect with fellow gardeners.', 'hobby', 'private', 'https://media.sojorn.net/garden-avatar.jpg', 4, 78, true),

('Home Cooking Masters', 'Share recipes, cooking techniques, and kitchen adventures. From beginners to gourmet chefs.', 'hobby', 'public', 'https://media.sojorn.net/cooking-avatar.jpg', 5, 312, true),

-- Sports Category
('Runners United', 'Training tips, race experiences, and running routes. Connect with runners of all levels in your area.', 'sports', 'public', 'https://media.sojorn.net/running-avatar.jpg', 6, 423, true),

('Yoga & Wellness', 'Daily practice sharing, meditation techniques, and wellness discussions. All levels welcome.', 'sports', 'public', 'https://media.sojorn.net/yoga-avatar.jpg', 7, 267, true),

('Cycling Community', 'Road cycling, mountain biking, and urban cycling. Share routes, gear reviews, and group ride info.', 'sports', 'private', 'https://media.sojorn.net/cycling-avatar.jpg', 8, 198, true),

-- Professional Category
('Startup Founders', 'Connect with fellow entrepreneurs, share experiences, and discuss the challenges of building companies.', 'professional', 'private', 'https://media.sojorn.net/startup-avatar.jpg', 9, 134, true),

('Remote Work Professionals', 'Tips, tools, and discussions about working remotely. Share your home office setup and productivity hacks.', 'professional', 'public', 'https://media.sojorn.net/remote-avatar.jpg', 10, 523, true),

('Software Developers', 'Code reviews, tech discussions, career advice, and programming language debates. All languages welcome.', 'professional', 'public', 'https://media.sojorn.net/dev-avatar.jpg', 11, 678, true),

-- Local Business Category
('Local Coffee Shops', 'Supporting local cafés and coffee culture. Share your favorite spots, reviews, and coffee experiences.', 'local_business', 'public', 'https://media.sojorn.net/coffee-avatar.jpg', 12, 89, true),

('Farmers Market Fans', 'Celebrating local farmers markets, farm-to-table eating, and supporting local agriculture.', 'local_business', 'public', 'https://media.sojorn.net/market-avatar.jpg', 13, 156, true),

-- Support Category
('Mental Health Support', 'A safe space to discuss mental health, share coping strategies, and find support. Confidential and respectful.', 'support', 'private', 'https://media.sojorn.net/mental-avatar.jpg', 14, 234, true),

('Parenting Community', 'Share parenting experiences, get advice, and connect with other parents. All parenting stages welcome.', 'support', 'public', 'https://media.sojorn.net/parenting-avatar.jpg', 15, 445, true),

-- Education Category
('Language Learning Exchange', 'Practice languages, find study partners, and share learning resources. All languages and levels.', 'education', 'public', 'https://media.sojorn.net/language-avatar.jpg', 16, 312, true),

('Book Club Central', 'Monthly book discussions, recommendations, and literary analysis. From classics to contemporary fiction.', 'education', 'private', 'https://media.sojorn.net/books-avatar.jpg', 17, 178, true);
`

	_, err = db.Exec(seedSQL)
	if err != nil {
		log.Printf("Error seeding groups: %v", err)
		return
	}

	fmt.Println("✅ Successfully seeded 15 demo groups across all categories")

	// Check if group_members table exists and has correct structure
	var membersExists bool
	err = db.QueryRow(`
		SELECT EXISTS (
			SELECT FROM information_schema.tables 
			WHERE table_name = 'group_members'
		);
	`).Scan(&membersExists)
	
	if err != nil {
		log.Printf("Error checking group_members table: %v", err)
		return
	}

	if !membersExists {
		fmt.Println("⚠️  group_members table doesn't exist, skipping member seeding")
	} else {
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
CROSS JOIN generate_series(1, LEAST(g.member_count, 50)) 
WHERE g.member_count > 0
ON CONFLICT (group_id, user_id) DO NOTHING;
`

		_, err = db.Exec(memberSQL)
		if err != nil {
			log.Printf("Error adding group members: %v", err)
		} else {
			fmt.Println("✅ Successfully added group members")
		}
	}

	// Verify the seeding
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM groups").Scan(&count)
	if err != nil {
		log.Printf("Error counting groups: %v", err)
		return
	}

	fmt.Printf("🎉 Groups seeding completed! Total groups: %d\n", count)

	// Show sample data
	rows, err := db.Query(`
		SELECT name, category, privacy, member_count 
		FROM groups 
		ORDER BY member_count DESC 
		LIMIT 5;
	`)
	if err != nil {
		log.Printf("Error querying sample groups: %v", err)
		return
	}
	defer rows.Close()

	fmt.Println("\n📊 Top 5 groups by member count:")
	for rows.Next() {
		var name, category, privacy string
		var memberCount int
		err := rows.Scan(&name, &category, &privacy, &memberCount)
		if err != nil {
			log.Printf("Error scanning row: %v", err)
			continue
		}
		fmt.Printf("  - %s (%s, %s, %d members)\n", name, category, privacy, memberCount)
	}
}
