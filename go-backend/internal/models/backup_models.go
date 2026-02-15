package models

import (
	"time"
	"github.com/google/uuid"
)

// SyncCode represents a temporary 6-digit code for device pairing
type SyncCode struct {
	ID               uuid.UUID  `json:"id" db:"id"`
	UserID           uuid.UUID  `json:"user_id" db:"user_id"`
	Code             string     `json:"code" db:"code"`
	DeviceFingerprint string     `json:"device_fingerprint" db:"device_fingerprint"`
	DeviceName       string     `json:"device_name" db:"device_name"`
	ExpiresAt        time.Time  `json:"expires_at" db:"expires_at"`
	UsedAt           *time.Time `json:"used_at" db:"used_at"`
	Attempts         int        `json:"attempts" db:"attempts"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
}

// CloudBackup represents an encrypted backup stored in cloud storage
type CloudBackup struct {
	ID            uuid.UUID `json:"id" db:"id"`
	UserID        uuid.UUID `json:"user_id" db:"user_id"`
	EncryptedBlob []byte    `json:"-" db:"encrypted_blob"` // Don't expose in JSON
	Salt          []byte    `json:"-" db:"salt"`           // Don't expose in JSON
	Nonce         []byte    `json:"-" db:"nonce"`          // Don't expose in JSON
	Mac           []byte    `json:"-" db:"mac"`            // Don't expose in JSON
	Version       int       `json:"version" db:"version"`
	DeviceName    string    `json:"device_name" db:"device_name"`
	SizeBytes     int64     `json:"size_bytes" db:"size_bytes"`
	CreatedAt     time.Time `json:"created_at" db:"created_at"`
}

// RecoveryGuardian represents a trusted contact for social recovery
type RecoveryGuardian struct {
	ID               uuid.UUID  `json:"id" db:"id"`
	UserID           uuid.UUID  `json:"user_id" db:"user_id"`
	GuardianUserID   uuid.UUID  `json:"guardian_user_id" db:"guardian_user_id"`
	ShardEncrypted   []byte     `json:"-" db:"shard_encrypted"` // Don't expose in JSON
	ShardIndex       int        `json:"shard_index" db:"shard_index"`
	Status           string     `json:"status" db:"status"` // pending, accepted, declined, revoked
	InvitedAt        time.Time  `json:"invited_at" db:"invited_at"`
	RespondedAt      *time.Time `json:"responded_at" db:"responded_at"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
}

// RecoverySession represents a recovery attempt
type RecoverySession struct {
	ID            uuid.UUID  `json:"id" db:"id"`
	UserID        uuid.UUID  `json:"user_id" db:"user_id"`
	Method        string     `json:"method" db:"method"` // social, email, questions
	ShardsReceived int       `json:"shards_received" db:"shards_received"`
	ShardsNeeded   int        `json:"shards_needed" db:"shards_needed"`
	Status         string     `json:"status" db:"status"` // pending, in_progress, completed, expired, failed
	ExpiresAt      time.Time  `json:"expires_at" db:"expires_at"`
	CompletedAt    *time.Time `json:"completed_at" db:"completed_at"`
	CreatedAt      time.Time  `json:"created_at" db:"created_at"`
}

// RecoveryShardSubmission represents an individual shard submission
type RecoveryShardSubmission struct {
	ID               uuid.UUID `json:"id" db:"id"`
	SessionID        uuid.UUID `json:"session_id" db:"session_id"`
	GuardianUserID   uuid.UUID `json:"guardian_user_id" db:"guardian_user_id"`
	ShardEncrypted   []byte    `json:"-" db:"shard_encrypted"` // Don't expose in JSON
	SubmittedAt      time.Time `json:"submitted_at" db:"submitted_at"`
	CreatedAt        time.Time `json:"created_at" db:"created_at"`
	ShardsReceived   int       `json:"shards_received,omitempty" db:"-"`
	ShardsNeeded     int       `json:"shards_needed,omitempty" db:"-"`
}

// BackupPreferences represents user backup settings
type BackupPreferences struct {
	ID                   uuid.UUID  `json:"id" db:"id"`
	UserID               uuid.UUID  `json:"user_id" db:"user_id"`
	CloudBackupEnabled   bool       `json:"cloud_backup_enabled" db:"cloud_backup_enabled"`
	AutoBackupEnabled    bool       `json:"auto_backup_enabled" db:"auto_backup_enabled"`
	BackupFrequencyHours int        `json:"backup_frequency_hours" db:"backup_frequency_hours"`
	LastBackupAt         *time.Time `json:"last_backup_at" db:"last_backup_at"`
	BackupPasswordHash   string     `json:"-" db:"backup_password_hash"`   // Don't expose in JSON
	BackupSalt           []byte     `json:"-" db:"backup_salt"`             // Don't expose in JSON
	CreatedAt            time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at" db:"updated_at"`
}

// UserDevice represents a registered user device
type UserDevice struct {
	ID               uuid.UUID  `json:"id" db:"id"`
	UserID           uuid.UUID  `json:"user_id" db:"user_id"`
	DeviceFingerprint string    `json:"device_fingerprint" db:"device_fingerprint"`
	DeviceName       string     `json:"device_name" db:"device_name"`
	DeviceType       string     `json:"device_type" db:"device_type"` // android, ios, web, desktop
	LastSeenAt       *time.Time `json:"last_seen_at" db:"last_seen_at"`
	IsActive         bool       `json:"is_active" db:"is_active"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
}

// Request/Response DTOs

// GenerateSyncCodeRequest represents a request to generate a sync code
type GenerateSyncCodeRequest struct {
	DeviceName       string `json:"device_name" binding:"required"`
	DeviceFingerprint string `json:"device_fingerprint" binding:"required"`
}

// GenerateSyncCodeResponse represents response with sync code
type GenerateSyncCodeResponse struct {
	Code      string    `json:"code"`
	ExpiresAt time.Time `json:"expires_at"`
	ExpiresIn int       `json:"expires_in_seconds"`
}

// VerifySyncCodeRequest represents a request to verify a sync code
type VerifySyncCodeRequest struct {
	Code             string `json:"code" binding:"required"`
	DeviceName       string `json:"device_name" binding:"required"`
	DeviceFingerprint string `json:"device_fingerprint" binding:"required"`
}

// VerifySyncCodeResponse represents response to sync code verification
type VerifySyncCodeResponse struct {
	Valid        bool   `json:"valid"`
	DeviceAID    string `json:"device_a_id,omitempty"`
	DeviceAName  string `json:"device_a_name,omitempty"`
	WebRTCOffer  string `json:"webrtc_offer,omitempty"`
	ErrorMessage  string `json:"error_message,omitempty"`
}

// UploadBackupRequest represents a request to upload a backup
type UploadBackupRequest struct {
	EncryptedBlob   string `json:"encrypted_blob" binding:"required"`
	Salt            string `json:"salt" binding:"required"`
	Nonce           string `json:"nonce" binding:"required"`
	Mac             string `json:"mac" binding:"required"`
	Version         int    `json:"version"`
	DeviceName      string `json:"device_name"`
}

// UploadBackupResponse represents response to backup upload
type UploadBackupResponse struct {
	BackupID   string    `json:"backup_id"`
	UploadedAt time.Time `json:"uploaded_at"`
	Size       int64     `json:"size"`
}

// DownloadBackupResponse represents response to backup download
type DownloadBackupResponse struct {
	EncryptedBlob string    `json:"encrypted_blob"`
	Salt          string    `json:"salt"`
	Nonce         string    `json:"nonce"`
	Mac           string    `json:"mac"`
	Version       int       `json:"version"`
	DeviceName    string    `json:"device_name"`
	CreatedAt     time.Time `json:"created_at"`
}

// ListBackupsResponse represents response to list backups request
type ListBackupsResponse struct {
	Backups []CloudBackup `json:"backups"`
}

// SetupSocialRecoveryRequest represents a request to setup social recovery
type SetupSocialRecoveryRequest struct {
	GuardianUserIDs []string `json:"guardian_user_ids" binding:"required,min=3,max=5"`
}

// InitiateRecoveryRequest represents a request to initiate recovery
type InitiateRecoveryRequest struct {
	Method string `json:"method" binding:"required,oneof=social email questions"`
}

// SubmitShardRequest represents a request to submit a recovery shard
type SubmitShardRequest struct {
	SessionID     string `json:"session_id" binding:"required"`
	ShardEncrypted string `json:"shard_encrypted" binding:"required"`
}

// SubmitShardResponse represents response to shard submission
type SubmitShardResponse struct {
	ShardsReceived int `json:"shards_received"`
	ShardsNeeded   int `json:"shards_needed"`
	CanComplete    bool `json:"can_complete"`
}

// CompleteRecoveryResponse represents response to complete recovery
type CompleteRecoveryResponse struct {
	Success      bool   `json:"success"`
	MasterKey    string `json:"master_key,omitempty"`
	ErrorMessage string `json:"error_message,omitempty"`
}

// UpdateBackupPreferencesRequest represents a request to update backup preferences
type UpdateBackupPreferencesRequest struct {
	CloudBackupEnabled    bool  `json:"cloud_backup_enabled"`
	AutoBackupEnabled     bool  `json:"auto_backup_enabled"`
	BackupFrequencyHours  int   `json:"backup_frequency_hours"`
	BackupPassword        string `json:"backup_password,omitempty"`
}
