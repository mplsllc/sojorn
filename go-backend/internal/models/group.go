package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type Group struct {
	ID             uuid.UUID       `json:"id" db:"id"`
	Name           string          `json:"name" db:"name"`
	Description    string          `json:"description" db:"description"`
	Type           string          `json:"type" db:"type"`       // 'geo', 'social', 'public_geo', 'private_capsule'
	Privacy        string          `json:"privacy" db:"privacy"` // 'public' or 'private'
	LocationCenter any             `json:"location_center,omitempty" db:"location_center"`
	Lat            *float64        `json:"lat,omitempty"`
	Long           *float64        `json:"long,omitempty"`
	RadiusMeters   int             `json:"radius_meters" db:"radius_meters"`
	AvatarURL      *string         `json:"avatar_url" db:"avatar_url"`
	CreatedBy      *uuid.UUID      `json:"created_by" db:"created_by"`
	MemberCount    int             `json:"member_count" db:"member_count"`
	IsActive       bool            `json:"is_active" db:"is_active"`
	IsEncrypted    bool            `json:"is_encrypted" db:"is_encrypted"`
	PublicKey      *string         `json:"public_key,omitempty" db:"public_key"`
	Settings       json.RawMessage `json:"settings,omitempty" db:"settings"`
	InviteCode     *string         `json:"invite_code,omitempty" db:"invite_code"`
	Category       string          `json:"category" db:"category"` // general, hobby, sports, professional, local_business, support, education
	KeyVersion     int             `json:"key_version" db:"key_version"`
	CreatedAt      time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at" db:"updated_at"`
}

// IsCapsule returns true if this group uses E2EE
func (g *Group) IsCapsule() bool {
	return g.Type == "private_capsule" && g.IsEncrypted
}

type GroupMember struct {
	ID                uuid.UUID `json:"id" db:"id"`
	GroupID           uuid.UUID `json:"group_id" db:"group_id"`
	UserID            uuid.UUID `json:"user_id" db:"user_id"`
	Role              string    `json:"role" db:"role"` // owner, admin, moderator, member
	EncryptedGroupKey *string   `json:"encrypted_group_key,omitempty" db:"encrypted_group_key"`
	KeyVersion        int       `json:"key_version" db:"key_version"`
	JoinedAt          time.Time `json:"joined_at" db:"joined_at"`
}

// CapsuleEntry holds E2EE content — the server NEVER decrypts this
type CapsuleEntry struct {
	ID               uuid.UUID  `json:"id" db:"id"`
	GroupID          uuid.UUID  `json:"group_id" db:"group_id"`
	AuthorID         uuid.UUID  `json:"author_id" db:"author_id"`
	IV               string     `json:"iv" db:"iv"`
	EncryptedPayload string     `json:"encrypted_payload" db:"encrypted_payload"`
	DataType         string     `json:"data_type" db:"data_type"` // chat, forum_post, document, image
	ReplyToID        *uuid.UUID `json:"reply_to_id,omitempty" db:"reply_to_id"`
	KeyVersion       int        `json:"key_version" db:"key_version"`
	IsDeleted        bool       `json:"is_deleted" db:"is_deleted"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at" db:"updated_at"`

	// Joined fields (not encrypted — public metadata)
	AuthorHandle      string `json:"author_handle,omitempty" db:"author_handle"`
	AuthorDisplayName string `json:"author_display_name,omitempty" db:"author_display_name"`
	AuthorAvatarURL   string `json:"author_avatar_url,omitempty" db:"author_avatar_url"`
}

// GroupWithDistance is returned by nearest-geo-group queries
type GroupWithDistance struct {
	Group
	DistanceMeters float64 `json:"distance_meters" db:"distance_meters"`
}

// GroupSettings defines what features are enabled for a group
type GroupSettings struct {
	Chat  bool `json:"chat"`
	Forum bool `json:"forum"`
	Files bool `json:"files"`
}

// CapsuleKey stores a per-user encrypted copy of a group's symmetric key.
// Security: Backend MUST only return rows WHERE user_id = authenticated user.
type CapsuleKey struct {
	ID               uuid.UUID `json:"id" db:"id"`
	UserID           uuid.UUID `json:"user_id" db:"user_id"`
	GroupID          uuid.UUID `json:"group_id" db:"group_id"`
	EncryptedKeyBlob string    `json:"encrypted_key_blob" db:"encrypted_key_blob"`
	KeyVersion       int       `json:"key_version" db:"key_version"`
	CreatedAt        time.Time `json:"created_at" db:"created_at"`
	UpdatedAt        time.Time `json:"updated_at" db:"updated_at"`
}

// CapsuleKeyBackup stores a PIN-encrypted backup of the user's private key.
// Zero-Knowledge: the server sees ONLY ciphertext — it cannot derive the PIN or key.
type CapsuleKeyBackup struct {
	ID        uuid.UUID `json:"id" db:"id"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	Salt      string    `json:"salt" db:"salt"`
	IV        string    `json:"iv" db:"iv"`
	Payload   string    `json:"payload" db:"payload"`
	PublicKey string    `json:"pub" db:"public_key"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}
