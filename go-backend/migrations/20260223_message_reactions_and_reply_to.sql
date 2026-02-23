-- Add reply_to_id for threaded replies in E2EE messages
ALTER TABLE public.secure_messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.secure_messages(id) ON DELETE SET NULL;

-- Message reactions (plaintext metadata — emoji on encrypted messages)
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.secure_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    emoji VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON public.message_reactions(message_id);
