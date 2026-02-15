-- Check if posts.status is an enum or text and add 'jailed' if needed
DO $$
BEGIN
    -- Check if post_status enum exists
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'post_status') THEN
        -- Add 'jailed' to post_status enum
        BEGIN
            ALTER TYPE post_status ADD VALUE IF NOT EXISTS 'jailed';
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END $$;

-- If posts.status is just text, no enum changes needed - 'jailed' will just work
