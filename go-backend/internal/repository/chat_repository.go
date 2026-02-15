package repository

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/patbritton/sojorn-backend/internal/models"
)

var ErrUnauthorized = errors.New("unauthorized")

type ChatRepository struct {
	pool *pgxpool.Pool
}

func NewChatRepository(pool *pgxpool.Pool) *ChatRepository {
	return &ChatRepository{pool: pool}
}

func (r *ChatRepository) CreateMessage(ctx context.Context, senderID, receiverID, conversationID uuid.UUID, ciphertext, iv, keyVersion, messageHeader string) (*models.EncryptedMessage, error) {
	var msg models.EncryptedMessage
	err := r.pool.QueryRow(ctx, `
		INSERT INTO public.secure_messages (conversation_id, sender_id, receiver_id, ciphertext, iv, key_version, message_header, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		RETURNING id, created_at
	`, conversationID, senderID, receiverID, ciphertext, iv, keyVersion, messageHeader).Scan(&msg.ID, &msg.CreatedAt)

	if err != nil {
		return nil, err
	}

	msg.ConversationID = conversationID
	msg.SenderID = senderID
	msg.ReceiverID = receiverID
	msg.Ciphertext = ciphertext
	msg.IV = iv
	msg.KeyVersion = keyVersion
	msg.MessageHeader = messageHeader

	return &msg, nil
}

func (r *ChatRepository) GetMessages(ctx context.Context, conversationID uuid.UUID, limit, offset int) ([]models.EncryptedMessage, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, conversation_id, sender_id, receiver_id, ciphertext, iv, key_version, message_header, created_at
		FROM public.secure_messages
		WHERE conversation_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, conversationID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []models.EncryptedMessage
	for rows.Next() {
		var m models.EncryptedMessage
		var ciphertextStr string
		err := rows.Scan(
			&m.ID, &m.ConversationID, &m.SenderID, &m.ReceiverID, &ciphertextStr, &m.IV, &m.KeyVersion, &m.MessageHeader, &m.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		m.Ciphertext = ciphertextStr
		messages = append(messages, m)
	}

	return messages, nil
}

func (r *ChatRepository) GetConversations(ctx context.Context, userID string) ([]models.Conversation, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT 
			c.id, c.participant_a, c.participant_b, c.created_at, c.last_message_at,
			pA.handle, pA.display_name, pA.avatar_url,
			pB.handle, pB.display_name, pB.avatar_url
		FROM public.encrypted_conversations c
		JOIN public.profiles pA ON c.participant_a = pA.id
		JOIN public.profiles pB ON c.participant_b = pB.id
		WHERE c.participant_a = $1::uuid OR c.participant_b = $1::uuid
		ORDER BY c.last_message_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var conversations []models.Conversation
	for rows.Next() {
		var c models.Conversation
		var pA models.Profile
		var pB models.Profile
		err := rows.Scan(
			&c.ID, &c.ParticipantA, &c.ParticipantB, &c.CreatedAt, &c.LastMessageAt,
			&pA.Handle, &pA.DisplayName, &pA.AvatarURL,
			&pB.Handle, &pB.DisplayName, &pB.AvatarURL,
		)
		if err != nil {
			return nil, err
		}
		pA.ID = c.ParticipantA
		pB.ID = c.ParticipantB
		c.ParticipantAProfile = &pA
		c.ParticipantBProfile = &pB
		conversations = append(conversations, c)
	}
	return conversations, nil
}

func (r *ChatRepository) GetMutualFollows(ctx context.Context, userID string) ([]models.Profile, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT p.id, p.handle, p.display_name, p.avatar_url
		FROM public.profiles p
		JOIN public.follows f1 ON f1.following_id = p.id AND f1.follower_id = $1::uuid AND f1.status = 'accepted'
		JOIN public.follows f2 ON f2.follower_id = p.id AND f2.following_id = $1::uuid AND f2.status = 'accepted'
		WHERE p.id != $1::uuid
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []models.Profile
	for rows.Next() {
		var p models.Profile
		if err := rows.Scan(&p.ID, &p.Handle, &p.DisplayName, &p.AvatarURL); err != nil {
			return nil, err
		}
		profiles = append(profiles, p)
	}
	return profiles, nil
}

func (r *ChatRepository) GetOrCreateConversation(ctx context.Context, userA, userB string) (string, error) {
	// Ensure userA < userB for consistency in unique constraint
	p1, p2 := userA, userB
	if p1 > p2 {
		p1, p2 = userB, userA
	}

	var id uuid.UUID
	err := r.pool.QueryRow(ctx, `
		INSERT INTO public.encrypted_conversations (participant_a, participant_b)
		VALUES ($1::uuid, $2::uuid)
		ON CONFLICT (participant_a, participant_b) 
		DO UPDATE SET last_message_at = NOW()
		RETURNING id
	`, p1, p2).Scan(&id)

	if err != nil {
		return "", err
	}
	return id.String(), nil
}

func (r *ChatRepository) GetParticipants(ctx context.Context, conversationID string) (string, string, error) {
	var pA, pB uuid.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT participant_a, participant_b FROM public.encrypted_conversations WHERE id = $1::uuid
	`, conversationID).Scan(&pA, &pB)

	if err != nil {
		return "", "", err
	}
	return pA.String(), pB.String(), nil
}

// DeleteConversation permanently deletes a conversation and all its messages
func (r *ChatRepository) DeleteConversation(ctx context.Context, conversationID uuid.UUID, userID string) error {
	// Verify user is a participant
	pA, pB, err := r.GetParticipants(ctx, conversationID.String())
	if err != nil {
		return err
	}
	if userID != pA && userID != pB {
		return ErrUnauthorized
	}

	// Delete all messages in conversation first
	_, err = r.pool.Exec(ctx, `
		DELETE FROM public.secure_messages WHERE conversation_id = $1
	`, conversationID)
	if err != nil {
		return err
	}

	// Delete the conversation
	_, err = r.pool.Exec(ctx, `
		DELETE FROM public.encrypted_conversations WHERE id = $1
	`, conversationID)
	return err
}

// GetMessageInfo retrieves conversation and participant info for a message
func (r *ChatRepository) GetMessageInfo(ctx context.Context, messageID uuid.UUID, conversationID, senderID, receiverID *uuid.UUID) error {
	return r.pool.QueryRow(ctx, `
		SELECT conversation_id, sender_id, receiver_id 
		FROM public.secure_messages 
		WHERE id = $1
	`, messageID).Scan(conversationID, senderID, receiverID)
}

// GetConversationParticipants retrieves both participant IDs from a conversation
func (r *ChatRepository) GetConversationParticipants(ctx context.Context, conversationID uuid.UUID, participant1ID, participant2ID *uuid.UUID) error {
	return r.pool.QueryRow(ctx, `
		SELECT participant1_id, participant2_id 
		FROM public.encrypted_conversations 
		WHERE id = $1
	`, conversationID).Scan(participant1ID, participant2ID)
}

// DeleteMessage permanently deletes a single message
func (r *ChatRepository) DeleteMessage(ctx context.Context, messageID uuid.UUID, userID string) error {
	// Verify user is the sender
	var senderID uuid.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT sender_id FROM public.secure_messages WHERE id = $1
	`, messageID).Scan(&senderID)
	if err != nil {
		return err
	}

	if senderID.String() != userID {
		return ErrUnauthorized
	}

	_, err = r.pool.Exec(ctx, `
		DELETE FROM public.secure_messages WHERE id = $1
	`, messageID)
	return err
}
