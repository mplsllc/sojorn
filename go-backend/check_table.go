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

	// Check if groups table exists
	var exists bool
	err = db.QueryRow(`
		SELECT EXISTS (
			SELECT FROM information_schema.tables 
			WHERE table_name = 'groups'
		);
	`).Scan(&exists)
	
	if err != nil {
		log.Printf("Error checking table: %v", err)
		return
	}

	if !exists {
		fmt.Println("❌ Groups table does not exist. Running migration...")
		
		// Run the groups migration
		migrationSQL := `
-- Groups System Database Schema
-- Creates tables for community groups, membership, join requests, and invitations

-- Main groups table
CREATE TABLE IF NOT EXISTS groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(50) NOT NULL,
  description TEXT,
  category VARCHAR(50) NOT NULL CHECK (category IN ('general', 'hobby', 'sports', 'professional', 'local_business', 'support', 'education')),
  avatar_url TEXT,
  banner_url TEXT,
  is_private BOOLEAN DEFAULT FALSE,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_count INTEGER DEFAULT 1,
  post_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(LOWER(name))
);

CREATE INDEX IF NOT EXISTS idx_groups_category ON groups(category);
CREATE INDEX IF NOT EXISTS idx_groups_created_by ON groups(created_by);
CREATE INDEX IF NOT EXISTS idx_groups_is_private ON groups(is_private);
CREATE INDEX IF NOT EXISTS idx_groups_member_count ON groups(member_count DESC);

-- Group members table with roles
CREATE TABLE IF NOT EXISTS group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_role ON group_members(role);

-- Join requests for private groups
CREATE TABLE IF NOT EXISTS group_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  message TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  reviewed_at TIMESTAMP,
  reviewed_by UUID REFERENCES users(id),
  UNIQUE(group_id, user_id, status)
);

CREATE INDEX IF NOT EXISTS idx_group_join_requests_group ON group_join_requests(group_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_user ON group_join_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_status ON group_join_requests(status);

-- Group invitations (for future use)
CREATE TABLE IF NOT EXISTS group_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  invited_user UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  message TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  UNIQUE(group_id, invited_user)
);

CREATE INDEX IF NOT EXISTS idx_group_invitations_group ON group_invitations(group_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_invited ON group_invitations(invited_user);
CREATE INDEX IF NOT EXISTS idx_group_invitations_status ON group_invitations(status);

-- Triggers for updating member and post counts
CREATE OR REPLACE FUNCTION update_group_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE groups SET member_count = member_count - 1 WHERE id = OLD.group_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_group_post_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE groups SET post_count = post_count + 1 WHERE id = NEW.group_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE groups SET post_count = post_count - 1 WHERE id = OLD.group_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS trigger_update_group_member_count ON group_members;
CREATE TRIGGER trigger_update_group_member_count
    AFTER INSERT OR DELETE ON group_members
    FOR EACH ROW EXECUTE FUNCTION update_group_member_count();

DROP TRIGGER IF EXISTS trigger_update_group_post_count ON posts;
CREATE TRIGGER trigger_update_group_post_count
    AFTER INSERT OR DELETE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_group_post_count()
    WHEN (NEW.group_id IS NOT NULL OR OLD.group_id IS NOT NULL);

-- Function to get suggested groups for a user
CREATE OR REPLACE FUNCTION get_suggested_groups(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    group_id UUID,
    name VARCHAR,
    description TEXT,
    category VARCHAR,
    is_private BOOLEAN,
    member_count INTEGER,
    post_count INTEGER,
    reason TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH user_following AS (
        SELECT followed_id FROM follows WHERE follower_id = p_user_id
    ),
    user_categories AS (
        SELECT DISTINCT category FROM user_category_settings WHERE user_id = p_user_id AND enabled = true
    )
    SELECT 
        g.id,
        g.name,
        g.description,
        g.category,
        g.is_private,
        g.member_count,
        g.post_count,
        CASE
            WHEN g.category IN (SELECT category FROM user_categories) THEN 'Based on your interests'
            WHEN EXISTS(SELECT 1 FROM group_members gm WHERE gm.group_id = g.id AND gm.user_id IN (SELECT followed_id FROM user_following)) THEN 'Friends are members'
            WHEN g.member_count > 100 THEN 'Popular community'
            ELSE 'Growing community'
        END as reason
    FROM groups g
    WHERE g.id NOT IN (
        SELECT group_id FROM group_members WHERE user_id = p_user_id
    )
    AND g.is_private = false
    ORDER BY 
        CASE 
            WHEN g.category IN (SELECT category FROM user_categories) THEN 1
            WHEN EXISTS(SELECT 1 FROM group_members gm WHERE gm.group_id = g.id AND gm.user_id IN (SELECT followed_id FROM user_following)) THEN 2
            ELSE 3
        END,
        g.member_count DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;
		`

		_, err = db.Exec(migrationSQL)
		if err != nil {
			log.Printf("Error running migration: %v", err)
			return
		}
		
		fmt.Println("✅ Groups migration completed successfully")
	} else {
		fmt.Println("✅ Groups table already exists")
	}

	// Now seed the data
	fmt.Println("🌱 Seeding groups data...")
}
