-- E2EE Chat tables
-- encrypted_conversations: server-blind conversation metadata (no message content)
-- secure_messages: server-blind ciphertext storage (server cannot read contents)

CREATE TABLE IF NOT EXISTS public.encrypted_conversations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_a    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    participant_b    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Enforce canonical ordering: participant_a < participant_b (UUID string sort)
    -- GetOrCreateConversation sorts before insert to guarantee this
    CONSTRAINT uq_conversation_pair UNIQUE (participant_a, participant_b),
    CONSTRAINT chk_no_self_chat CHECK (participant_a != participant_b)
);

CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_participant_a ON public.encrypted_conversations(participant_a);
CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_participant_b ON public.encrypted_conversations(participant_b);
CREATE INDEX IF NOT EXISTS idx_encrypted_conversations_last_message ON public.encrypted_conversations(last_message_at DESC);

CREATE TABLE IF NOT EXISTS public.secure_messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES public.encrypted_conversations(id) ON DELETE CASCADE,
    sender_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    -- Server stores blind ciphertext only — plaintext never touches the server
    ciphertext       TEXT NOT NULL,
    message_header   TEXT NOT NULL DEFAULT '',  -- X3DH header (base64 JSON): ik, ek, opk_id, mac
    iv               TEXT NOT NULL DEFAULT '',  -- AES-GCM nonce (base64)
    key_version      TEXT NOT NULL DEFAULT 'x3dh',
    message_type     INTEGER NOT NULL DEFAULT 1, -- 1=standard, 2=command (delete/resync)
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at     TIMESTAMPTZ,
    read_at          TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ  -- NULL = no expiry
);

CREATE INDEX IF NOT EXISTS idx_secure_messages_conversation ON public.secure_messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_secure_messages_receiver ON public.secure_messages(receiver_id, delivered_at NULLS FIRST);
CREATE INDEX IF NOT EXISTS idx_secure_messages_expires ON public.secure_messages(expires_at) WHERE expires_at IS NOT NULL;

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
