-- Sojorn — Consolidated Initial Schema
-- Copyright (c) 2026 MPLS LLC
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- This file creates ALL tables needed for a fresh Sojorn install.
-- Run with: go run cmd/migrate/main.go
-- Every statement uses IF NOT EXISTS for idempotent re-runs.

-- ============================================================================
-- Extensions
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "postgis";    -- geography columns, ST_ functions

-- ============================================================================
-- Custom ENUM types
-- ============================================================================
DO $$ BEGIN
    CREATE TYPE post_status AS ENUM ('active', 'flagged', 'removed', 'expired', 'jailed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 1. Core Auth: users
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email               TEXT        NOT NULL UNIQUE,
    encrypted_password  TEXT        NOT NULL,
    status              TEXT        NOT NULL DEFAULT 'pending',  -- pending, active, deactivated, pending_deletion, banned, suspended
    mfa_enabled         BOOLEAN     NOT NULL DEFAULT FALSE,
    last_login          TIMESTAMPTZ,
    email_newsletter    BOOLEAN     NOT NULL DEFAULT FALSE,
    email_contact       BOOLEAN     NOT NULL DEFAULT FALSE,
    neighborhood_group_id UUID,     -- FK added after groups table
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

-- ============================================================================
-- 2. Profiles
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id                       UUID        PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    handle                   TEXT        UNIQUE,
    display_name             TEXT,
    bio                      TEXT,
    avatar_url               TEXT,
    cover_url                TEXT,
    is_official              BOOLEAN     DEFAULT FALSE,
    is_private               BOOLEAN     DEFAULT FALSE,
    is_verified              BOOLEAN     DEFAULT FALSE,
    beacon_enabled           BOOLEAN     NOT NULL DEFAULT FALSE,
    location                 TEXT,
    website                  TEXT,
    interests                TEXT[]      DEFAULT '{}',
    origin_country           TEXT,
    strikes                  INT         NOT NULL DEFAULT 0,
    identity_key             TEXT,
    registration_id          INT,
    encrypted_private_key    TEXT,
    has_completed_onboarding BOOLEAN     NOT NULL DEFAULT FALSE,
    role                     TEXT        NOT NULL DEFAULT 'user',  -- user, admin
    birth_month              INT         NOT NULL DEFAULT 0,
    birth_year               INT         NOT NULL DEFAULT 0,
    status_text              TEXT,
    status_updated_at        TIMESTAMPTZ,
    metadata_fields          JSONB       DEFAULT '[]'::jsonb,
    unread_notification_count INT        NOT NULL DEFAULT 0,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_handle ON public.profiles(handle);

-- ============================================================================
-- 3. Trust / Harmony
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.trust_state (
    user_id            UUID        PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    harmony_score      INT         NOT NULL DEFAULT 50,
    tier               TEXT        NOT NULL DEFAULT 'new',  -- new, trusted, established
    posts_today        INT         NOT NULL DEFAULT 0,
    last_post_at       TIMESTAMPTZ,
    last_harmony_calc_at TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 4. Social graph: follows, blocks, circle
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.follows (
    follower_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    following_id UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status       TEXT        NOT NULL DEFAULT 'accepted',  -- pending, accepted
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_following ON public.follows(following_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower  ON public.follows(follower_id);

CREATE TABLE IF NOT EXISTS public.blocks (
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE IF NOT EXISTS public.circle_members (
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, member_id)
);

-- ============================================================================
-- 5. Categories
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.categories (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    slug                TEXT        NOT NULL UNIQUE,
    name                TEXT        NOT NULL,
    description         TEXT,
    icon_url            TEXT,
    is_sensitive        BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    official_account_id TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_category_settings (
    user_id     UUID    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category_id UUID    NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id, category_id)
);

-- Legacy alias referenced by account deletion
CREATE TABLE IF NOT EXISTS public.user_category_preferences (
    user_id     UUID    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category_id UUID    NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id, category_id)
);

-- ============================================================================
-- 6. Posts
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.posts (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id         UUID          REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id       UUID          REFERENCES public.categories(id) ON DELETE SET NULL,
    body              TEXT          NOT NULL DEFAULT '',
    status            post_status   NOT NULL DEFAULT 'active',
    tone_label        TEXT,
    cis_score         DOUBLE PRECISION,
    image_url         TEXT,
    video_url         TEXT,
    thumbnail_url     TEXT,
    first_frame_url   TEXT,
    duration_ms       INT           NOT NULL DEFAULT 0,
    body_format       TEXT          NOT NULL DEFAULT 'plain',  -- plain, markdown
    background_id     TEXT,
    tags              TEXT[]        DEFAULT '{}',
    is_beacon         BOOLEAN       NOT NULL DEFAULT FALSE,
    beacon_type       TEXT,
    location          GEOGRAPHY(Point, 4326),
    confidence_score  DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_active_beacon  BOOLEAN       NOT NULL DEFAULT FALSE,
    is_priority       BOOLEAN       NOT NULL DEFAULT FALSE,
    severity          TEXT          NOT NULL DEFAULT 'medium',
    incident_status   TEXT          NOT NULL DEFAULT 'active',
    radius            INT           NOT NULL DEFAULT 500,
    allow_chain       BOOLEAN       NOT NULL DEFAULT FALSE,
    chain_parent_id   UUID          REFERENCES public.posts(id) ON DELETE SET NULL,
    visibility        TEXT          NOT NULL DEFAULT 'public',  -- public, followers, circle, neighborhood
    is_nsfw           BOOLEAN       NOT NULL DEFAULT FALSE,
    nsfw_reason       TEXT          NOT NULL DEFAULT '',
    expires_at        TIMESTAMPTZ,
    overlay_json      TEXT,
    audio_overlay_url TEXT,
    group_id          UUID,  -- FK added after groups table
    link_preview_url          TEXT,
    link_preview_title        TEXT,
    link_preview_description  TEXT,
    link_preview_image_url    TEXT,
    link_preview_site_name    TEXT,
    frames_moderated_at       TIMESTAMPTZ,
    pinned_at         TIMESTAMPTZ,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    edited_at         TIMESTAMPTZ,
    deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_posts_author      ON public.posts(author_id);
CREATE INDEX IF NOT EXISTS idx_posts_created      ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_beacon       ON public.posts(is_beacon) WHERE is_beacon = TRUE;
CREATE INDEX IF NOT EXISTS idx_posts_beacon_priority ON public.posts(is_priority) WHERE is_beacon = TRUE AND is_priority = TRUE;
CREATE INDEX IF NOT EXISTS idx_posts_location     ON public.posts USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_posts_group_id     ON public.posts(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_chain_parent ON public.posts(chain_parent_id) WHERE chain_parent_id IS NOT NULL;

-- ============================================================================
-- 7. Post engagement: likes, saves, reactions, hides, metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.post_likes (
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.post_saves (
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.post_reactions (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    emoji   TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (post_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_post_reactions_post ON public.post_reactions(post_id);

CREATE TABLE IF NOT EXISTS public.post_hides (
    user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    post_id   UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);

CREATE TABLE IF NOT EXISTS public.post_metrics (
    post_id       UUID PRIMARY KEY REFERENCES public.posts(id) ON DELETE CASCADE,
    like_count    INT NOT NULL DEFAULT 0,
    save_count    INT NOT NULL DEFAULT 0,
    view_count    INT NOT NULL DEFAULT 0,
    comment_count INT NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.post_interactions (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type    TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.post_categories (
    post_id     UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, category_id)
);

-- ============================================================================
-- 8. Comments
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.comments (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id   UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    body      TEXT NOT NULL,
    status    TEXT NOT NULL DEFAULT 'active',
    tone_label TEXT,
    cis_score  DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_comments_post ON public.comments(post_id);

-- ============================================================================
-- 9. Hashtags & Mentions
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.hashtags (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name           TEXT        NOT NULL UNIQUE,
    display_name   TEXT        NOT NULL DEFAULT '',
    use_count      INT         NOT NULL DEFAULT 0,
    trending_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_trending    BOOLEAN     NOT NULL DEFAULT FALSE,
    is_featured    BOOLEAN     NOT NULL DEFAULT FALSE,
    category       TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.post_hashtags (
    post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    hashtag_id UUID NOT NULL REFERENCES public.hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, hashtag_id)
);

CREATE INDEX IF NOT EXISTS idx_post_hashtags_hashtag ON public.post_hashtags(hashtag_id);

CREATE TABLE IF NOT EXISTS public.hashtag_follows (
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    hashtag_id UUID NOT NULL REFERENCES public.hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, hashtag_id)
);

CREATE TABLE IF NOT EXISTS public.post_mentions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id           UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    mentioned_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (post_id, mentioned_user_id)
);

-- ============================================================================
-- 10. Suggested Users (discover page)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.suggested_users (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reason    TEXT NOT NULL DEFAULT 'popular',
    category  TEXT,
    score     DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 11. Beacon vouches & reports
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.beacon_vouches (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beacon_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (beacon_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.beacon_reports (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beacon_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (beacon_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_beacon_vouches_beacon ON public.beacon_vouches(beacon_id);
CREATE INDEX IF NOT EXISTS idx_beacon_reports_beacon ON public.beacon_reports(beacon_id);

-- Legacy alias referenced by account deletion
CREATE TABLE IF NOT EXISTS public.beacon_votes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beacon_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    vote_type  TEXT NOT NULL DEFAULT 'vouch',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (beacon_id, user_id)
);

-- ============================================================================
-- 12. Groups
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.groups (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT        NOT NULL,
    description         TEXT        NOT NULL DEFAULT '',
    type                VARCHAR(50) NOT NULL DEFAULT 'social',  -- geo, social, public_geo, private_capsule, neighborhood
    privacy             VARCHAR(20) NOT NULL DEFAULT 'public',  -- public, private
    location_center     GEOGRAPHY(Point, 4326),
    radius_meters       INT,
    avatar_url          TEXT,
    created_by          UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    member_count        INT         NOT NULL DEFAULT 0,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_encrypted        BOOLEAN     NOT NULL DEFAULT FALSE,
    public_key          TEXT,
    settings            JSONB       NOT NULL DEFAULT '{}',
    invite_code         TEXT        UNIQUE,
    category            TEXT        NOT NULL DEFAULT 'general',
    key_version         INT         NOT NULL DEFAULT 0,
    key_rotation_needed BOOLEAN     NOT NULL DEFAULT FALSE,
    chat_enabled        BOOLEAN     NOT NULL DEFAULT TRUE,
    forum_enabled       BOOLEAN     NOT NULL DEFAULT TRUE,
    vault_enabled       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Now add the FK from users.neighborhood_group_id
DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT fk_users_neighborhood_group
        FOREIGN KEY (neighborhood_group_id) REFERENCES public.groups(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- And posts.group_id
DO $$ BEGIN
    ALTER TABLE public.posts ADD CONSTRAINT fk_posts_group
        FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.group_members (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id            UUID        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id             UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role                TEXT        NOT NULL DEFAULT 'member',  -- owner, admin, moderator, member
    encrypted_group_key TEXT,
    key_version         INT         NOT NULL DEFAULT 0,
    joined_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_group ON public.group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user  ON public.group_members(user_id);

CREATE TABLE IF NOT EXISTS public.group_posts (
    group_id UUID        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    post_id  UUID        NOT NULL REFERENCES public.posts(id)  ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_group_posts_group_id ON public.group_posts(group_id, added_at DESC);

CREATE TABLE IF NOT EXISTS public.group_messages (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id  UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body      TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_group_messages_group ON public.group_messages(group_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.group_forum_threads (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id         UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    author_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL DEFAULT '',
    category         TEXT,
    reply_count      INT  NOT NULL DEFAULT 0,
    is_pinned        BOOLEAN NOT NULL DEFAULT FALSE,
    is_locked        BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted       BOOLEAN NOT NULL DEFAULT FALSE,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_group_forum_threads_group    ON public.group_forum_threads(group_id, last_activity_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_forum_threads_category ON public.group_forum_threads(group_id, category) WHERE is_deleted = FALSE;

CREATE TABLE IF NOT EXISTS public.group_forum_replies (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id  UUID NOT NULL REFERENCES public.group_forum_threads(id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_group_forum_replies_thread ON public.group_forum_replies(thread_id, created_at);

CREATE TABLE IF NOT EXISTS public.group_member_keys (
    group_id      UUID    NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id       UUID    NOT NULL REFERENCES public.users(id)  ON DELETE CASCADE,
    key_version   INT     NOT NULL,
    encrypted_key TEXT    NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (group_id, user_id, key_version)
);

CREATE INDEX IF NOT EXISTS idx_group_member_keys_group ON public.group_member_keys(group_id, key_version);

-- ============================================================================
-- 13. Capsule (E2EE groups) keys & entries
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.capsule_entries (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id           UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    author_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    iv                 TEXT NOT NULL,
    encrypted_payload  TEXT NOT NULL,
    data_type          TEXT NOT NULL DEFAULT 'chat',  -- chat, forum_post, document, image
    reply_to_id        UUID REFERENCES public.capsule_entries(id) ON DELETE SET NULL,
    key_version        INT  NOT NULL DEFAULT 0,
    is_deleted         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_capsule_entries_group ON public.capsule_entries(group_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.capsule_keys (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    group_id           UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    encrypted_key_blob TEXT NOT NULL,
    key_version        INT  NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, group_id, key_version)
);

CREATE TABLE IF NOT EXISTS public.capsule_key_backups (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    salt        TEXT NOT NULL,
    iv          TEXT NOT NULL,
    payload     TEXT NOT NULL,
    public_key  TEXT NOT NULL DEFAULT '',
    backup_type TEXT NOT NULL DEFAULT 'passphrase',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, backup_type)
);

-- ============================================================================
-- 14. E2EE Direct Messaging
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.encrypted_conversations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_a    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    participant_b    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_conversation_pair UNIQUE (participant_a, participant_b),
    CONSTRAINT chk_no_self_chat CHECK (participant_a != participant_b)
);

CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_participant_a  ON public.encrypted_conversations(participant_a);
CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_participant_b  ON public.encrypted_conversations(participant_b);
CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_last_message   ON public.encrypted_conversations(last_message_at DESC);

CREATE TABLE IF NOT EXISTS public.secure_messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES public.encrypted_conversations(id) ON DELETE CASCADE,
    sender_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ciphertext       TEXT NOT NULL,
    message_header   TEXT NOT NULL DEFAULT '',
    iv               TEXT NOT NULL DEFAULT '',
    key_version      TEXT NOT NULL DEFAULT 'x3dh',
    message_type     INTEGER NOT NULL DEFAULT 1,
    reply_to_id      UUID REFERENCES public.secure_messages(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at     TIMESTAMPTZ,
    read_at          TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_secure_messages_conversation ON public.secure_messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_secure_messages_receiver     ON public.secure_messages(receiver_id, delivered_at NULLS FIRST);
CREATE INDEX IF NOT EXISTS idx_secure_messages_expires      ON public.secure_messages(expires_at) WHERE expires_at IS NOT NULL;

-- Auto-update last_message_at on conversation when a message is inserted
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.encrypted_conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_conversation_last_message ON public.secure_messages;
CREATE TRIGGER trg_update_conversation_last_message
    AFTER INSERT ON public.secure_messages
    FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();

CREATE TABLE IF NOT EXISTS public.message_reactions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.secure_messages(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    emoji      VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON public.message_reactions(message_id);

-- Legacy encrypted_messages table (referenced by notification badge query)
CREATE TABLE IF NOT EXISTS public.encrypted_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ciphertext  TEXT NOT NULL,
    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 15. Signal Protocol key storage
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.signed_prekeys (
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    key_id     INT  NOT NULL,
    public_key TEXT NOT NULL,
    signature  TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, key_id)
);

CREATE TABLE IF NOT EXISTS public.one_time_prekeys (
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    key_id     INT  NOT NULL,
    public_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, key_id)
);

CREATE TABLE IF NOT EXISTS public.signal_keys (
    user_id    UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    key_data   JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.e2ee_sessions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_b     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.e2ee_session_state (
    session_id UUID PRIMARY KEY REFERENCES public.e2ee_sessions(id) ON DELETE CASCADE,
    state_data JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 16. Notifications
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.notifications (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type       TEXT NOT NULL,
    actor_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id    UUID REFERENCES public.posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
    is_read    BOOLEAN NOT NULL DEFAULT FALSE,
    metadata   JSONB   NOT NULL DEFAULT '{}',
    group_key  TEXT,
    priority   TEXT    NOT NULL DEFAULT 'normal',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_user   ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id) WHERE is_read = FALSE AND archived_at IS NULL;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
    user_id                UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    push_enabled           BOOLEAN NOT NULL DEFAULT TRUE,
    push_likes             BOOLEAN NOT NULL DEFAULT TRUE,
    push_comments          BOOLEAN NOT NULL DEFAULT TRUE,
    push_replies           BOOLEAN NOT NULL DEFAULT TRUE,
    push_mentions          BOOLEAN NOT NULL DEFAULT TRUE,
    push_follows           BOOLEAN NOT NULL DEFAULT TRUE,
    push_follow_requests   BOOLEAN NOT NULL DEFAULT TRUE,
    push_messages          BOOLEAN NOT NULL DEFAULT TRUE,
    push_saves             BOOLEAN NOT NULL DEFAULT TRUE,
    push_beacons           BOOLEAN NOT NULL DEFAULT TRUE,
    email_enabled          BOOLEAN NOT NULL DEFAULT FALSE,
    email_digest_frequency TEXT    NOT NULL DEFAULT 'never',
    quiet_hours_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
    quiet_hours_start      TIME,
    quiet_hours_end        TIME,
    show_badge_count       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
    user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token        TEXT NOT NULL,
    device_type  TEXT NOT NULL DEFAULT 'web',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, token)
);

-- ============================================================================
-- 17. Auth tokens
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.auth_tokens (
    token      TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type       TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.verification_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.password_reset_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 18. MFA & WebAuthn
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.mfa_secrets (
    user_id        UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    secret         TEXT NOT NULL,
    recovery_codes TEXT[] NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Legacy alias used by some code paths
CREATE TABLE IF NOT EXISTS public.user_mfa_secrets (
    user_id        UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    secret_key     TEXT NOT NULL,
    recovery_codes TEXT[] NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.webauthn_credentials (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    credential_id    BYTEA NOT NULL,
    public_key       BYTEA NOT NULL,
    attestation_type TEXT  NOT NULL DEFAULT '',
    aaguid           UUID,
    sign_count       INT   NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webauthn_user ON public.webauthn_credentials(user_id);

-- ============================================================================
-- 19. User settings & privacy
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id              UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    theme                TEXT DEFAULT 'system',
    language             TEXT DEFAULT 'en',
    notifications_enabled BOOLEAN DEFAULT TRUE,
    email_notifications  BOOLEAN DEFAULT FALSE,
    push_notifications   BOOLEAN DEFAULT TRUE,
    content_filter_level TEXT DEFAULT 'medium',
    auto_play_videos     BOOLEAN DEFAULT TRUE,
    data_saver_mode      BOOLEAN DEFAULT FALSE,
    default_post_ttl     INT,
    nsfw_enabled         BOOLEAN DEFAULT FALSE,
    nsfw_blur_enabled    BOOLEAN DEFAULT TRUE,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profile_privacy_settings (
    user_id                UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    show_location          BOOLEAN DEFAULT TRUE,
    show_interests         BOOLEAN DEFAULT TRUE,
    profile_visibility     TEXT DEFAULT 'public',
    posts_visibility       TEXT DEFAULT 'public',
    saved_visibility       TEXT DEFAULT 'private',
    follow_request_policy  TEXT DEFAULT 'auto_accept',
    default_post_visibility TEXT DEFAULT 'public',
    is_private_profile     BOOLEAN DEFAULT FALSE,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 20. Moderation & Reports
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_user_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id         UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    comment_id      UUID REFERENCES public.comments(id) ON DELETE SET NULL,
    group_id        UUID REFERENCES public.groups(id),
    neighborhood_id UUID,  -- FK added after neighborhood_seeds
    violation_type  TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    status          TEXT NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_group_id        ON public.reports(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_neighborhood_id ON public.reports(neighborhood_id) WHERE neighborhood_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.abuse_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    blocked_id     UUID NOT NULL,
    blocked_handle TEXT NOT NULL DEFAULT '',
    actor_ip       TEXT NOT NULL DEFAULT '',
    user_id        UUID,  -- used by account deletion
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.moderation_flags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id     UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    comment_id  UUID REFERENCES public.comments(id) ON DELETE SET NULL,
    user_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    flag_reason TEXT NOT NULL DEFAULT '',
    scores      JSONB NOT NULL DEFAULT '{}',
    status      TEXT  NOT NULL DEFAULT 'pending',
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pending_moderation (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    content_id UUID,
    type       TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.content_strikes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category        TEXT NOT NULL DEFAULT '',
    content_snippet TEXT NOT NULL DEFAULT '',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_status_history (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT NOT NULL,
    reason     TEXT NOT NULL DEFAULT '',
    changed_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 21. Violations & Appeals
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_violations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    moderation_flag_id      UUID REFERENCES public.moderation_flags(id) ON DELETE SET NULL,
    violation_type          TEXT NOT NULL,
    violation_reason        TEXT NOT NULL DEFAULT '',
    severity_score          DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_appealable           BOOLEAN NOT NULL DEFAULT TRUE,
    appeal_deadline         TIMESTAMPTZ,
    status                  TEXT NOT NULL DEFAULT 'active',
    content_deleted         BOOLEAN NOT NULL DEFAULT FALSE,
    content_deletion_reason TEXT NOT NULL DEFAULT '',
    account_status_change   TEXT NOT NULL DEFAULT '',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_appeals (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_violation_id UUID NOT NULL REFERENCES public.user_violations(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    appeal_reason     TEXT NOT NULL,
    appeal_context    TEXT NOT NULL DEFAULT '',
    evidence_urls     TEXT[] DEFAULT '{}',
    status            TEXT NOT NULL DEFAULT 'pending',
    reviewed_by       UUID,
    review_decision   TEXT NOT NULL DEFAULT '',
    reviewed_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_violation_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    violation_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    total_violations    INT NOT NULL DEFAULT 0,
    hard_violations     INT NOT NULL DEFAULT 0,
    soft_violations     INT NOT NULL DEFAULT 0,
    appeals_filed       INT NOT NULL DEFAULT 0,
    appeals_upheld      INT NOT NULL DEFAULT 0,
    appeals_overturned  INT NOT NULL DEFAULT 0,
    content_deletions   INT NOT NULL DEFAULT 0,
    account_warnings    INT NOT NULL DEFAULT 0,
    account_suspensions INT NOT NULL DEFAULT 0,
    current_status      TEXT NOT NULL DEFAULT 'active',
    ban_expiry          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.appeal_guidelines (
    id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_type               TEXT NOT NULL UNIQUE,
    max_appeals_per_month        INT  NOT NULL DEFAULT 3,
    appeal_window_hours          INT  NOT NULL DEFAULT 72,
    auto_ban_threshold           INT  NOT NULL DEFAULT 5,
    hard_violation_ban_threshold INT  NOT NULL DEFAULT 3,
    is_active                    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 22. AI Moderation
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ai_moderation_config (
    moderation_type   TEXT PRIMARY KEY,
    model_id          TEXT NOT NULL DEFAULT '',
    model_name        TEXT NOT NULL DEFAULT '',
    system_prompt     TEXT NOT NULL DEFAULT '',
    enabled           BOOLEAN NOT NULL DEFAULT TRUE,
    engines           TEXT[] DEFAULT '{}',
    sightengine_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_by        UUID,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ai_moderation_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type     TEXT NOT NULL,
    content_id       UUID,
    author_id        UUID,
    content_snippet  TEXT NOT NULL DEFAULT '',
    decision         TEXT NOT NULL DEFAULT '',
    flag_reason      TEXT NOT NULL DEFAULT '',
    ai_provider      TEXT NOT NULL DEFAULT '',
    scores_hate      DOUBLE PRECISION DEFAULT 0,
    scores_greed     DOUBLE PRECISION DEFAULT 0,
    scores_delusion  DOUBLE PRECISION DEFAULT 0,
    raw_scores       JSONB DEFAULT '{}',
    or_decision      TEXT DEFAULT '',
    or_scores        JSONB DEFAULT '{}',
    admin_feedback   TEXT,
    feedback_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_moderation_log_author ON public.ai_moderation_log(author_id);

-- ============================================================================
-- 23. Feed Algorithm
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.post_feed_scores (
    post_id             UUID PRIMARY KEY REFERENCES public.posts(id) ON DELETE CASCADE,
    score               DOUBLE PRECISION NOT NULL DEFAULT 0,
    engagement_score    DOUBLE PRECISION DEFAULT 0,
    quality_score       DOUBLE PRECISION DEFAULT 0,
    recency_score       DOUBLE PRECISION DEFAULT 0,
    network_score       DOUBLE PRECISION DEFAULT 0,
    personalization     DOUBLE PRECISION DEFAULT 0,
    tone_score          DOUBLE PRECISION DEFAULT 0,
    video_boost_score   DOUBLE PRECISION DEFAULT 0,
    harmony_score       DOUBLE PRECISION DEFAULT 0,
    moderation_penalty  DOUBLE PRECISION DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_post_feed_scores_score_desc ON public.post_feed_scores(score DESC);

CREATE TABLE IF NOT EXISTS public.user_feed_impressions (
    user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    post_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    shown_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_user_feed_impressions_user ON public.user_feed_impressions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_feed_impressions_post ON public.user_feed_impressions(post_id);

CREATE TABLE IF NOT EXISTS public.feed_engagement (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    type    TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.algorithm_config (
    key         VARCHAR(100) PRIMARY KEY,
    value       VARCHAR(100) NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default algorithm config
INSERT INTO public.algorithm_config (key, value, description) VALUES
    ('feed_recency_weight',             '0.20', 'Weight for post recency in feed ranking'),
    ('feed_engagement_weight',          '0.28', 'Weight for engagement in feed ranking (content-first)'),
    ('feed_harmony_weight',             '0.0',  'Weight for author harmony — disabled (content-first)'),
    ('feed_diversity_weight',           '0.10', 'Weight for content diversity'),
    ('feed_cooling_multiplier',         '0.20', 'Score multiplier for previously-seen posts'),
    ('feed_diversity_personal_pct',     '60',   'Percentage of feed from top personal scores'),
    ('feed_diversity_category_pct',     '20',   'Percentage of feed from under-represented categories'),
    ('feed_diversity_discovery_pct',    '20',   'Percentage of feed from authors viewer does not follow'),
    ('moderation_auto_flag_threshold',  '0.70', 'AI score threshold for auto-flagging'),
    ('moderation_auto_remove_threshold','0.95', 'AI score threshold for auto-removal'),
    ('feed_tone_weight',                '0.15', 'Weight for content tone in feed ranking (content-first)'),
    ('feed_quality_weight',             '0.22', 'Weight for content quality in feed ranking (content-first)'),
    ('feed_network_weight',             '0.0',  'Weight for network connections — disabled (content-first)'),
    ('feed_personalization_weight',     '0.07', 'Weight for personalization in feed ranking'),
    ('tone_positive_boost',             '0.15', 'Score boost for positive tone posts'),
    ('tone_negative_penalty',           '0.15', 'Score penalty for negative tone posts'),
    ('tone_hostile_penalty',            '0.40', 'Score penalty for hostile tone posts'),
    ('feed_video_boost_weight',         '0.08', 'Weight for video watch-time boost'),
    ('video_base_boost',                '0.05', 'Base score boost for all video content'),
    ('harmony_floor',                   '0.20', 'Minimum harmony factor for new users'),
    ('feed_moderation_penalty_weight',  '0.0',  'Weight for moderation penalty — disabled (content-first)'),
    ('moderation_strike_penalty',       '0.15', 'Score penalty per active strike'),
    ('moderation_flag_penalty',         '0.10', 'Score penalty per pending flag'),
    ('moderation_flag_penalty_cap',     '0.30', 'Maximum total flag penalty'),
    ('video_moderation_frame_count',    '5',    'Number of frames to extract from videos for SightEngine moderation')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.post_views (
    post_id          UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    view_count       INT  DEFAULT 1,
    total_duration_ms INT DEFAULT 0,
    last_watch_pct   INT  DEFAULT 0,
    viewed_at        TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_views_post_id ON public.post_views(post_id);

-- ============================================================================
-- 24. Neighborhoods & Board
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.neighborhood_seeds (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    city          TEXT NOT NULL DEFAULT '',
    state         TEXT NOT NULL DEFAULT '',
    zip_code      TEXT NOT NULL DEFAULT '',
    country       TEXT NOT NULL DEFAULT '',
    lat           DOUBLE PRECISION NOT NULL,
    lng           DOUBLE PRECISION NOT NULL,
    radius_meters INT  NOT NULL DEFAULT 1000,
    group_id      UUID REFERENCES public.groups(id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add FK from reports.neighborhood_id now that neighborhood_seeds exists
DO $$ BEGIN
    ALTER TABLE public.reports ADD CONSTRAINT fk_reports_neighborhood
        FOREIGN KEY (neighborhood_id) REFERENCES public.neighborhood_seeds(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.board_entries (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    image_url   TEXT,
    topic       TEXT NOT NULL DEFAULT 'general',
    tag         VARCHAR(20),
    lat         DOUBLE PRECISION NOT NULL,
    long        DOUBLE PRECISION NOT NULL,
    location    GEOGRAPHY(Point, 4326),
    upvotes     INT     NOT NULL DEFAULT 0,
    reply_count INT     NOT NULL DEFAULT 0,
    is_pinned   BOOLEAN NOT NULL DEFAULT FALSE,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_board_entries_location ON public.board_entries USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_board_entries_tag      ON public.board_entries(tag) WHERE tag IS NOT NULL;

-- Auto-set location from lat/long on insert/update
CREATE OR REPLACE FUNCTION board_entry_set_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location := ST_SetSRID(ST_Point(NEW.long, NEW.lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_board_entry_location ON public.board_entries;
CREATE TRIGGER trg_board_entry_location
    BEFORE INSERT OR UPDATE ON public.board_entries
    FOR EACH ROW EXECUTE FUNCTION board_entry_set_location();

CREATE TABLE IF NOT EXISTS public.board_replies (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id   UUID NOT NULL REFERENCES public.board_entries(id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    body       TEXT NOT NULL,
    upvotes    INT  NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_board_replies_entry ON public.board_replies(entry_id, created_at);

CREATE TABLE IF NOT EXISTS public.board_votes (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    entry_id UUID REFERENCES public.board_entries(id) ON DELETE CASCADE,
    reply_id UUID REFERENCES public.board_replies(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_board_votes_user_entry ON public.board_votes(user_id, entry_id);
CREATE INDEX IF NOT EXISTS idx_board_votes_user_reply ON public.board_votes(user_id, reply_id);

-- ============================================================================
-- 25. Events
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.events (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    group_id          UUID        REFERENCES public.groups(id) ON DELETE SET NULL,
    title             VARCHAR(255) NOT NULL,
    description       TEXT,
    start_time        TIMESTAMPTZ NOT NULL,
    end_time          TIMESTAMPTZ,
    location_name     VARCHAR(255),
    location_lat      DOUBLE PRECISION,
    location_long     DOUBLE PRECISION,
    cover_image_url   TEXT,
    category          VARCHAR(50)  NOT NULL DEFAULT 'general',
    status            VARCHAR(20)  NOT NULL DEFAULT 'published',
    capacity          INT,
    rsvp_count        INT          NOT NULL DEFAULT 0,
    is_online         BOOLEAN      NOT NULL DEFAULT FALSE,
    online_url        TEXT,
    deleted_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.event_rsvps (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID        NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status      VARCHAR(20) NOT NULL DEFAULT 'going',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS events_location_idx    ON public.events(location_lat, location_long) WHERE location_lat IS NOT NULL AND location_long IS NOT NULL AND status = 'published' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS events_start_time_idx  ON public.events(start_time ASC) WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS events_organizer_idx   ON public.events(organizer_id, start_time ASC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS event_rsvps_user_idx   ON public.event_rsvps(user_id, event_id);

-- Keep rsvp_count denormalised
CREATE OR REPLACE FUNCTION update_event_rsvp_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'going' THEN
        UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
    ELSIF TG_OP = 'DELETE' AND OLD.status = 'going' THEN
        UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = OLD.event_id;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'going' AND NEW.status != 'going' THEN
            UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = NEW.event_id;
        ELSIF OLD.status != 'going' AND NEW.status = 'going' THEN
            UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_rsvp_count ON public.event_rsvps;
CREATE TRIGGER trg_event_rsvp_count
    AFTER INSERT OR UPDATE OR DELETE ON public.event_rsvps
    FOR EACH ROW EXECUTE FUNCTION update_event_rsvp_count();

-- ============================================================================
-- 26. Group Events
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.group_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    location_name   TEXT,
    lat             DOUBLE PRECISION,
    long            DOUBLE PRECISION,
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ,
    is_public       BOOLEAN NOT NULL DEFAULT FALSE,
    cover_image_url TEXT,
    max_attendees   INT,
    source          TEXT NOT NULL DEFAULT 'user',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.group_event_rsvps (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id   UUID NOT NULL REFERENCES public.group_events(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status     TEXT NOT NULL DEFAULT 'going' CHECK (status IN ('going', 'interested', 'not_going')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_events_group  ON public.group_events(group_id);
CREATE INDEX IF NOT EXISTS idx_group_events_starts ON public.group_events(starts_at);
CREATE INDEX IF NOT EXISTS idx_group_events_public ON public.group_events(is_public) WHERE is_public = TRUE;
CREATE INDEX IF NOT EXISTS idx_group_event_rsvps_event ON public.group_event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_group_event_rsvps_user  ON public.group_event_rsvps(user_id);

CREATE TABLE IF NOT EXISTS public.external_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source          TEXT NOT NULL,
    external_id     TEXT NOT NULL,
    group_event_id  UUID REFERENCES public.group_events(id) ON DELETE SET NULL,
    external_url    TEXT,
    raw_data        JSONB,
    last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_external_events_source ON public.external_events(source, external_id);
CREATE INDEX IF NOT EXISTS idx_external_events_group  ON public.external_events(group_event_id);

-- ============================================================================
-- 27. Beacon Alerts (external feeds)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.beacon_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id     TEXT,
    source          TEXT NOT NULL,
    beacon_type     TEXT NOT NULL DEFAULT 'hazard',
    severity        TEXT NOT NULL DEFAULT 'medium',
    title           TEXT NOT NULL DEFAULT '',
    body            TEXT NOT NULL DEFAULT '',
    lat             DOUBLE PRECISION NOT NULL,
    lng             DOUBLE PRECISION NOT NULL,
    location        GEOGRAPHY(Point, 4326),
    radius          INT  NOT NULL DEFAULT 500,
    image_url       TEXT,
    video_url       TEXT,
    is_official     BOOLEAN NOT NULL DEFAULT FALSE,
    official_source TEXT,
    author_id       TEXT,
    author_handle   TEXT,
    author_display  TEXT,
    status          TEXT NOT NULL DEFAULT 'active',
    incident_status TEXT NOT NULL DEFAULT 'active',
    confidence      DOUBLE PRECISION DEFAULT 1.0,
    vouch_count     INT  NOT NULL DEFAULT 0,
    report_count    INT  NOT NULL DEFAULT 0,
    tags            TEXT[] DEFAULT '{}',
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_beacon_alerts_location   ON public.beacon_alerts USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_status     ON public.beacon_alerts(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_expires    ON public.beacon_alerts(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_source     ON public.beacon_alerts(source);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_admin_list ON public.beacon_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_source_status ON public.beacon_alerts(source, status);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_beacon_type   ON public.beacon_alerts(beacon_type);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_severity      ON public.beacon_alerts(severity);

-- Auto-set location from lat/lng
CREATE OR REPLACE FUNCTION beacon_alerts_set_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location := ST_SetSRID(ST_Point(NEW.lng, NEW.lat), 4326)::geography;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_beacon_alerts_set_location ON public.beacon_alerts;
CREATE TRIGGER trg_beacon_alerts_set_location
    BEFORE INSERT OR UPDATE ON public.beacon_alerts
    FOR EACH ROW EXECUTE FUNCTION beacon_alerts_set_location();

CREATE TABLE IF NOT EXISTS public.beacon_feed_config (
    source       TEXT PRIMARY KEY,
    enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    last_error   TEXT,
    alert_count  INT NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.beacon_feed_config (source) VALUES
    ('mn511'), ('mn511_camera'), ('mn511_sign'), ('mn511_weather'), ('iced')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 28. Profile Layouts & Dashboard Layouts
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profile_layouts (
    user_id               UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    widgets               JSONB NOT NULL DEFAULT '[]'::jsonb,
    theme                 TEXT  NOT NULL DEFAULT 'default',
    accent_color          TEXT,
    banner_image_url      TEXT,
    desktop_left_sidebar  JSONB NOT NULL DEFAULT '[]',
    desktop_right_sidebar JSONB NOT NULL DEFAULT '[]',
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.dashboard_layouts (
    user_id       UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    left_sidebar  JSONB NOT NULL DEFAULT '[]'::jsonb,
    right_sidebar JSONB NOT NULL DEFAULT '[]'::jsonb,
    feed_topbar   JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 29. Social Imports (YouTube/TikTok etc.)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.social_imports (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform      TEXT NOT NULL,
    external_id   TEXT NOT NULL,
    external_url  TEXT NOT NULL,
    post_id       UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    author_id     UUID NOT NULL REFERENCES public.profiles(id),
    imported_by   UUID NOT NULL,
    media_url     TEXT,
    original_date TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(platform, external_id)
);

CREATE INDEX IF NOT EXISTS idx_social_imports_platform_ext ON public.social_imports(platform, external_id);
CREATE INDEX IF NOT EXISTS idx_social_imports_author       ON public.social_imports(author_id);

-- ============================================================================
-- 30. Sounds (audio library)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sounds (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    uploader_id    UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    source_post_id UUID        REFERENCES public.posts(id) ON DELETE SET NULL,
    title          TEXT        NOT NULL,
    r2_key         TEXT        NOT NULL,
    bucket         TEXT        NOT NULL DEFAULT 'user',
    duration_ms    INTEGER,
    use_count      INTEGER     NOT NULL DEFAULT 0,
    is_active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sounds_use_count ON public.sounds(use_count DESC);
CREATE INDEX IF NOT EXISTS idx_sounds_bucket    ON public.sounds(bucket, is_active);

-- ============================================================================
-- 31. Sponsored Posts
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sponsored_posts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    advertiser_name TEXT NOT NULL DEFAULT '',
    budget_cents    INT  NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 32. Backup & Recovery
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sync_codes (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    code               TEXT NOT NULL,
    device_fingerprint TEXT NOT NULL DEFAULT '',
    device_name        TEXT NOT NULL DEFAULT '',
    expires_at         TIMESTAMPTZ NOT NULL,
    used_at            TIMESTAMPTZ,
    attempts           INT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cloud_backups (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    encrypted_blob  BYTEA NOT NULL,
    salt            BYTEA NOT NULL,
    nonce           BYTEA NOT NULL,
    mac             BYTEA NOT NULL,
    version         INT   NOT NULL DEFAULT 1,
    device_name     TEXT  NOT NULL DEFAULT '',
    size_bytes      BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recovery_guardians (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    guardian_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    guardian_id       UUID,  -- alias column for account deletion
    shard_encrypted   BYTEA,
    shard_index       INT NOT NULL DEFAULT 0,
    status            TEXT NOT NULL DEFAULT 'pending',
    invited_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recovery_sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    method           TEXT NOT NULL DEFAULT 'social',
    shards_received  INT  NOT NULL DEFAULT 0,
    shards_needed    INT  NOT NULL DEFAULT 3,
    status           TEXT NOT NULL DEFAULT 'pending',
    expires_at       TIMESTAMPTZ NOT NULL,
    completed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recovery_shard_submissions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id        UUID NOT NULL REFERENCES public.recovery_sessions(id) ON DELETE CASCADE,
    guardian_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    shard_encrypted   BYTEA NOT NULL,
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.backup_preferences (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    cloud_backup_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
    auto_backup_enabled   BOOLEAN NOT NULL DEFAULT FALSE,
    backup_frequency_hours INT    NOT NULL DEFAULT 24,
    last_backup_at        TIMESTAMPTZ,
    backup_password_hash  TEXT,
    backup_salt           BYTEA,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_devices (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    device_fingerprint TEXT NOT NULL,
    device_name        TEXT NOT NULL DEFAULT '',
    device_type        TEXT NOT NULL DEFAULT 'web',
    last_seen_at       TIMESTAMPTZ,
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, device_fingerprint)
);

-- ============================================================================
-- 33. Admin: Audit Log
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID,
    admin_id    UUID,  -- some code paths use admin_id instead of actor_id
    action      TEXT NOT NULL,
    target_type TEXT NOT NULL DEFAULT '',
    target_id   UUID,
    details     JSONB DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created ON public.audit_log(created_at DESC);

-- ============================================================================
-- 34. Waitlist
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.waitlist (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT NOT NULL,
    name          TEXT NOT NULL DEFAULT '',
    referral_code TEXT,
    invited_by    TEXT,
    status        TEXT NOT NULL DEFAULT 'waiting',
    notes         TEXT NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 35. Email Templates
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.email_templates (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL DEFAULT '',
    description  TEXT NOT NULL DEFAULT '',
    subject      TEXT NOT NULL DEFAULT '',
    title        TEXT NOT NULL DEFAULT '',
    header       TEXT NOT NULL DEFAULT '',
    content      TEXT NOT NULL DEFAULT '',
    button_text  TEXT NOT NULL DEFAULT '',
    button_url   TEXT NOT NULL DEFAULT '',
    button_color TEXT NOT NULL DEFAULT '',
    footer       TEXT NOT NULL DEFAULT '',
    text_body    TEXT NOT NULL DEFAULT '',
    enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 36. Username Claim Requests
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.username_claim_requests (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    handle     TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 37. Instance Configuration (self-hosted settings)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.instance_extensions (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    enabled     BOOLEAN NOT NULL DEFAULT FALSE,
    enabled_at  TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    config      JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.instance_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT INTO public.instance_config (key, value) VALUES
    ('instance_name',         'Sojorn'),
    ('instance_description',  'A self-hosted social network'),
    ('instance_logo_url',     ''),
    ('instance_accent_color', ''),
    ('registration_mode',     'open')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- 38. Trending Score Function (called by scheduled job)
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_trending_scores()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.hashtags h SET
        trending_score = COALESCE(sub.score, 0),
        is_trending = COALESCE(sub.score, 0) > 0,
        use_count = COALESCE(sub.total_count, h.use_count)
    FROM (
        SELECT
            ph.hashtag_id,
            COUNT(*) FILTER (WHERE ph.created_at > NOW() - INTERVAL '24 hours') AS score,
            COUNT(*) AS total_count
        FROM public.post_hashtags ph
        GROUP BY ph.hashtag_id
    ) sub
    WHERE h.id = sub.hashtag_id;
END;
$$;

-- ============================================================================
-- Done.
-- ============================================================================
