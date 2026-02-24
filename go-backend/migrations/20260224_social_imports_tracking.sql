-- Track imported social media items to avoid duplicates
CREATE TABLE IF NOT EXISTS social_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform TEXT NOT NULL,              -- youtube, tiktok, facebook, instagram
    external_id TEXT NOT NULL,           -- platform-specific content ID
    external_url TEXT NOT NULL,          -- original URL on platform
    post_id UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    author_id UUID NOT NULL REFERENCES public.profiles(id),
    imported_by UUID NOT NULL,           -- admin who imported
    media_url TEXT,                      -- R2 URL after download
    original_date TIMESTAMPTZ,           -- original upload date on platform
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(platform, external_id)
);

CREATE INDEX idx_social_imports_platform_ext ON social_imports (platform, external_id);
CREATE INDEX idx_social_imports_author ON social_imports (author_id);
