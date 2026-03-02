-- Add first_frame_url column to posts table
-- Stores the WebP thumbnail extracted from the first frame of a video at upload time.
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS first_frame_url TEXT;
