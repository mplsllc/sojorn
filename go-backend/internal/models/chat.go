// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package models

import (
	"time"

	"github.com/google/uuid"
)

type Conversation struct {
	ID            uuid.UUID `json:"id" db:"id"`
	ParticipantA  uuid.UUID `json:"participant_a" db:"participant_a"`
	ParticipantB  uuid.UUID `json:"participant_b" db:"participant_b"`
	CreatedAt     time.Time `json:"created_at" db:"created_at"`
	LastMessageAt time.Time `json:"last_message_at" db:"last_message_at"`

	// Profiles for response hydration
	ParticipantAProfile *Profile `json:"participant_a_profile,omitempty"`
	ParticipantBProfile *Profile `json:"participant_b_profile,omitempty"`
}

type EncryptedMessage struct {
	ID             uuid.UUID  `json:"id" db:"id"`
	ConversationID uuid.UUID  `json:"conversation_id" db:"conversation_id"`
	SenderID       uuid.UUID  `json:"sender_id" db:"sender_id"`
	ReceiverID     uuid.UUID  `json:"receiver_id" db:"receiver_id"`
	Ciphertext     string     `json:"ciphertext" db:"ciphertext"`
	MessageHeader  string     `json:"message_header" db:"message_header"` // Legacy/Optional
	IV             string     `json:"iv" db:"iv"`                         // Base64
	KeyVersion     string     `json:"key_version" db:"key_version"`
	MessageType    int        `json:"message_type" db:"message_type"`
	ReplyToID      *uuid.UUID `json:"reply_to_id,omitempty" db:"reply_to_id"`
	CreatedAt      time.Time  `json:"created_at" db:"created_at"`
	DeliveredAt    *time.Time `json:"delivered_at,omitempty" db:"delivered_at"`
	ReadAt         *time.Time `json:"read_at,omitempty" db:"read_at"`
	ExpiresAt      *time.Time `json:"expires_at,omitempty" db:"expires_at"`
	Reactions      []Reaction `json:"reactions,omitempty"`
}

type Reaction struct {
	ID        uuid.UUID `json:"id"`
	MessageID uuid.UUID `json:"message_id"`
	UserID    uuid.UUID `json:"user_id"`
	Emoji     string    `json:"emoji"`
	CreatedAt time.Time `json:"created_at"`
}
