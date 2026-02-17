package repository

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

type BackupRepository struct {
	pool *pgxpool.Pool
}

func NewBackupRepository(pool *pgxpool.Pool) *BackupRepository {
	return &BackupRepository{pool: pool}
}

// Sync Code Methods

func (r *BackupRepository) GenerateSyncCode(ctx context.Context, userID uuid.UUID, deviceName, deviceFingerprint string) (*models.SyncCode, error) {
	// Generate 6-digit code
	code := generateRandomCode(6)
	expiresAt := time.Now().Add(5 * time.Minute)

	// Check rate limit: max 5 codes per hour per user
	var recentCodes int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM sync_codes 
		WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 hour'
	`, userID).Scan(&recentCodes)
	if err != nil {
		return nil, fmt.Errorf("failed to check rate limit: %w", err)
	}
	if recentCodes >= 5 {
		return nil, fmt.Errorf("rate limit exceeded: too many codes generated")
	}

	// Insert sync code
	var syncCode models.SyncCode
	err = r.pool.QueryRow(ctx, `
		INSERT INTO sync_codes (user_id, code, device_fingerprint, device_name, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, code, device_fingerprint, device_name, expires_at, used_at, attempts, created_at
	`, userID, code, deviceFingerprint, deviceName, expiresAt).Scan(
		&syncCode.ID, &syncCode.Code, &syncCode.DeviceFingerprint, &syncCode.DeviceName,
		&syncCode.ExpiresAt, &syncCode.UsedAt, &syncCode.Attempts, &syncCode.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to generate sync code: %w", err)
	}

	return &syncCode, nil
}

func (r *BackupRepository) VerifySyncCode(ctx context.Context, code string, userID, requestingUserID uuid.UUID, deviceName, deviceFingerprint string) (*models.SyncCode, error) {
	var syncCode models.SyncCode
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, code, device_fingerprint, device_name, expires_at, used_at, attempts, created_at
		FROM sync_codes
		WHERE code = $1 AND used_at IS NULL
	`, code).Scan(
		&syncCode.ID, &syncCode.UserID, &syncCode.Code, &syncCode.DeviceFingerprint,
		&syncCode.DeviceName, &syncCode.ExpiresAt, &syncCode.UsedAt, &syncCode.Attempts, &syncCode.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("invalid sync code")
		}
		return nil, fmt.Errorf("failed to verify sync code: %w", err)
	}

	// Check if expired
	if time.Now().After(syncCode.ExpiresAt) {
		return nil, fmt.Errorf("sync code has expired")
	}

	// Check attempts
	if syncCode.Attempts >= 3 {
		return nil, fmt.Errorf("too many attempts for this sync code")
	}

	// Increment attempts
	_, err = r.pool.Exec(ctx, `
		UPDATE sync_codes SET attempts = attempts + 1 WHERE id = $1
	`, syncCode.ID)
	if err != nil {
		return nil, fmt.Errorf("failed to increment attempts: %w", err)
	}

	return &syncCode, nil
}

// Backup Methods

func (r *BackupRepository) UploadBackup(ctx context.Context, backup *models.CloudBackup) (uuid.UUID, error) {
	// Keep only 3 most recent backups per user
	_, err := r.pool.Exec(ctx, `
		DELETE FROM cloud_backups 
		WHERE user_id = $1 AND id NOT IN (
			SELECT id FROM cloud_backups 
			WHERE user_id = $1 
			ORDER BY created_at DESC 
			LIMIT 3
		)
	`, backup.UserID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to clean old backups: %w", err)
	}

	// Insert new backup
	var backupID uuid.UUID
	err = r.pool.QueryRow(ctx, `
		INSERT INTO cloud_backups (user_id, encrypted_blob, salt, nonce, mac, version, device_name, size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id
	`, backup.UserID, backup.EncryptedBlob, backup.Salt, backup.Nonce, backup.Mac,
		backup.Version, backup.DeviceName, backup.SizeBytes).Scan(&backupID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to upload backup: %w", err)
	}

	return backupID, nil
}

func (r *BackupRepository) GetLatestBackup(ctx context.Context, userID uuid.UUID) (*models.CloudBackup, error) {
	var backup models.CloudBackup
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, encrypted_blob, salt, nonce, mac, version, device_name, size_bytes, created_at
		FROM cloud_backups
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, userID).Scan(
		&backup.ID, &backup.UserID, &backup.EncryptedBlob, &backup.Salt, &backup.Nonce,
		&backup.Mac, &backup.Version, &backup.DeviceName, &backup.SizeBytes, &backup.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("no backup found")
		}
		return nil, fmt.Errorf("failed to get latest backup: %w", err)
	}

	return &backup, nil
}

func (r *BackupRepository) GetBackup(ctx context.Context, backupID, userID uuid.UUID) (*models.CloudBackup, error) {
	var backup models.CloudBackup
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, encrypted_blob, salt, nonce, mac, version, device_name, size_bytes, created_at
		FROM cloud_backups
		WHERE id = $1 AND user_id = $2
	`, backupID, userID).Scan(
		&backup.ID, &backup.UserID, &backup.EncryptedBlob, &backup.Salt, &backup.Nonce,
		&backup.Mac, &backup.Version, &backup.DeviceName, &backup.SizeBytes, &backup.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("backup not found")
		}
		return nil, fmt.Errorf("failed to get backup: %w", err)
	}

	return &backup, nil
}

func (r *BackupRepository) ListBackups(ctx context.Context, userID uuid.UUID) ([]models.CloudBackup, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, encrypted_blob, salt, nonce, mac, version, device_name, size_bytes, created_at
		FROM cloud_backups
		WHERE user_id = $1
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list backups: %w", err)
	}
	defer rows.Close()

	var backups []models.CloudBackup
	for rows.Next() {
		var backup models.CloudBackup
		err := rows.Scan(
			&backup.ID, &backup.UserID, &backup.EncryptedBlob, &backup.Salt, &backup.Nonce,
			&backup.Mac, &backup.Version, &backup.DeviceName, &backup.SizeBytes, &backup.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan backup: %w", err)
		}
		backups = append(backups, backup)
	}

	return backups, nil
}

func (r *BackupRepository) DeleteBackup(ctx context.Context, backupID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM cloud_backups WHERE id = $1 AND user_id = $2
	`, backupID, userID)
	if err != nil {
		return fmt.Errorf("failed to delete backup: %w", err)
	}
	return nil
}

// Social Recovery Methods

func (r *BackupRepository) SetupSocialRecovery(ctx context.Context, userID uuid.UUID, guardianIDs []uuid.UUID, masterSecret []byte) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Clear existing guardians
	_, err = tx.Exec(ctx, "DELETE FROM recovery_guardians WHERE user_id = $1", userID)
	if err != nil {
		return fmt.Errorf("failed to clear existing guardians: %w", err)
	}

	// Insert new guardians
	for i, guardianID := range guardianIDs {
		// In a real implementation, you'd encrypt the shard with guardian's public key
		// For now, we'll just store the master secret (simplified)
		_, err = tx.Exec(ctx, `
			INSERT INTO recovery_guardians (user_id, guardian_user_id, shard_encrypted, shard_index)
			VALUES ($1, $2, $3, $4)
		`, userID, guardianID, masterSecret, i)
		if err != nil {
			return fmt.Errorf("failed to insert guardian: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *BackupRepository) InitiateRecovery(ctx context.Context, userID uuid.UUID, method string) (*models.RecoverySession, error) {
	var session models.RecoverySession
	expiresAt := time.Now().Add(24 * time.Hour) // 24 hour expiry

	err := r.pool.QueryRow(ctx, `
		INSERT INTO recovery_sessions (user_id, method, shards_needed, expires_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id, user_id, method, shards_received, shards_needed, status, expires_at, completed_at, created_at
	`, userID, method, 3, expiresAt).Scan(
		&session.ID, &session.UserID, &session.Method, &session.ShardsReceived,
		&session.ShardsNeeded, &session.Status, &session.ExpiresAt, &session.CompletedAt, &session.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to initiate recovery: %w", err)
	}

	return &session, nil
}

func (r *BackupRepository) SubmitShard(ctx context.Context, sessionID, guardianUserID uuid.UUID, shardEncrypted []byte) (*models.RecoveryShardSubmission, error) {
	// Get session details
	var shardsNeeded int
	err := r.pool.QueryRow(ctx, `
		SELECT shards_needed FROM recovery_sessions WHERE id = $1 AND status = 'pending'
	`, sessionID).Scan(&shardsNeeded)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired recovery session: %w", err)
	}

	// Insert shard submission
	var submission models.RecoveryShardSubmission
	err = r.pool.QueryRow(ctx, `
		INSERT INTO recovery_shard_submissions (session_id, guardian_user_id, shard_encrypted)
		VALUES ($1, $2, $3)
		RETURNING id, session_id, guardian_user_id, shard_encrypted, submitted_at, created_at
	`, sessionID, guardianUserID, shardEncrypted).Scan(
		&submission.ID, &submission.SessionID, &submission.GuardianUserID,
		&submission.ShardEncrypted, &submission.SubmittedAt, &submission.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to submit shard: %w", err)
	}

	// Count total shards received
	var shardsReceived int
	err = r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM recovery_shard_submissions WHERE session_id = $1
	`, sessionID).Scan(&shardsReceived)
	if err != nil {
		return nil, fmt.Errorf("failed to count shards: %w", err)
	}

	// Update session if threshold reached
	if shardsReceived >= shardsNeeded {
		_, err = r.pool.Exec(ctx, `
			UPDATE recovery_sessions 
			SET shards_received = $1, status = 'in_progress' 
			WHERE id = $2
		`, shardsReceived, sessionID)
		if err != nil {
			return nil, fmt.Errorf("failed to update session: %w", err)
		}
	}

	submission.ShardsReceived = shardsReceived
	submission.ShardsNeeded = shardsNeeded

	return &submission, nil
}

func (r *BackupRepository) CompleteRecovery(ctx context.Context, sessionID, userID uuid.UUID) ([]byte, error) {
	// Get all shards for this session
	rows, err := r.pool.Query(ctx, `
		SELECT shard_encrypted FROM recovery_shard_submissions 
		WHERE session_id = $1
	`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to get shards: %w", err)
	}
	defer rows.Close()

	var shards [][]byte
	for rows.Next() {
		var shard []byte
		err := rows.Scan(&shard)
		if err != nil {
			return nil, fmt.Errorf("failed to scan shard: %w", err)
		}
		shards = append(shards, shard)
	}

	// Check if we have enough shards (simplified - in real implementation use Shamir's)
	if len(shards) < 3 {
		return nil, fmt.Errorf("insufficient shards to complete recovery")
	}

	// For this simplified implementation, we'll just return the first shard
	// In a real implementation, you'd use Shamir's Secret Sharing to reconstruct
	masterKey := shards[0]

	// Mark session as completed
	_, err = r.pool.Exec(ctx, `
		UPDATE recovery_sessions 
		SET status = 'completed', completed_at = NOW() 
		WHERE id = $1
	`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to complete session: %w", err)
	}

	return masterKey, nil
}

// Backup Preferences Methods

func (r *BackupRepository) GetBackupPreferences(ctx context.Context, userID uuid.UUID) (*models.BackupPreferences, error) {
	var prefs models.BackupPreferences
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, cloud_backup_enabled, auto_backup_enabled, backup_frequency_hours, 
			   last_backup_at, backup_password_hash, backup_salt, created_at, updated_at
		FROM backup_preferences
		WHERE user_id = $1
	`, userID).Scan(
		&prefs.ID, &prefs.UserID, &prefs.CloudBackupEnabled, &prefs.AutoBackupEnabled,
		&prefs.BackupFrequencyHours, &prefs.LastBackupAt, &prefs.BackupPasswordHash,
		&prefs.BackupSalt, &prefs.CreatedAt, &prefs.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			// Create default preferences
			return r.createDefaultPreferences(ctx, userID)
		}
		return nil, fmt.Errorf("failed to get backup preferences: %w", err)
	}

	return &prefs, nil
}

func (r *BackupRepository) createDefaultPreferences(ctx context.Context, userID uuid.UUID) (*models.BackupPreferences, error) {
	var prefs models.BackupPreferences
	err := r.pool.QueryRow(ctx, `
		INSERT INTO backup_preferences (user_id)
		VALUES ($1)
		RETURNING id, user_id, cloud_backup_enabled, auto_backup_enabled, backup_frequency_hours, 
				  last_backup_at, backup_password_hash, backup_salt, created_at, updated_at
	`, userID).Scan(
		&prefs.ID, &prefs.UserID, &prefs.CloudBackupEnabled, &prefs.AutoBackupEnabled,
		&prefs.BackupFrequencyHours, &prefs.LastBackupAt, &prefs.BackupPasswordHash,
		&prefs.BackupSalt, &prefs.CreatedAt, &prefs.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create default preferences: %w", err)
	}

	return &prefs, nil
}

func (r *BackupRepository) UpdateBackupPreferences(ctx context.Context, userID uuid.UUID, req models.UpdateBackupPreferencesRequest) error {
	// In a real implementation, you'd hash the backup password with Argon2id
	var passwordHash *string
	var salt *[]byte
	if req.BackupPassword != "" {
		// Generate salt
		saltBytes := make([]byte, 32)
		if _, err := rand.Read(saltBytes); err != nil {
			return fmt.Errorf("failed to generate salt: %w", err)
		}
		salt = &saltBytes
		
		// For now, just store the password as hash (simplified)
		hash := req.BackupPassword // In real implementation: Argon2id hash
		passwordHash = &hash
	}

	_, err := r.pool.Exec(ctx, `
		UPDATE backup_preferences 
		SET cloud_backup_enabled = $1, auto_backup_enabled = $2, backup_frequency_hours = $3,
			backup_password_hash = $4, backup_salt = $5, updated_at = NOW()
		WHERE user_id = $6
	`, req.CloudBackupEnabled, req.AutoBackupEnabled, req.BackupFrequencyHours,
		passwordHash, salt, userID)
	if err != nil {
		return fmt.Errorf("failed to update backup preferences: %w", err)
	}

	return nil
}

func (r *BackupRepository) UpdateLastBackupTime(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE backup_preferences SET last_backup_at = NOW() WHERE user_id = $1
	`, userID)
	if err != nil {
		return fmt.Errorf("failed to update last backup time: %w", err)
	}
	return nil
}

// Device Management Methods

func (r *BackupRepository) RegisterDevice(ctx context.Context, userID uuid.UUID, deviceName, deviceFingerprint, deviceType string) (*models.UserDevice, error) {
	var device models.UserDevice
	err := r.pool.QueryRow(ctx, `
		INSERT INTO user_devices (user_id, device_fingerprint, device_name, device_type, last_seen_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (user_id, device_fingerprint) 
		DO UPDATE SET device_name = EXCLUDED.device_name, last_seen_at = NOW(), is_active = true
		RETURNING id, user_id, device_fingerprint, device_name, device_type, last_seen_at, is_active, created_at
	`, userID, deviceFingerprint, deviceName, deviceType).Scan(
		&device.ID, &device.UserID, &device.DeviceFingerprint, &device.DeviceName,
		&device.DeviceType, &device.LastSeenAt, &device.IsActive, &device.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to register device: %w", err)
	}

	return &device, nil
}

func (r *BackupRepository) GetUserDevices(ctx context.Context, userID uuid.UUID) ([]models.UserDevice, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, device_fingerprint, device_name, device_type, last_seen_at, is_active, created_at
		FROM user_devices
		WHERE user_id = $1
		ORDER BY last_seen_at DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user devices: %w", err)
	}
	defer rows.Close()

	var devices []models.UserDevice
	for rows.Next() {
		var device models.UserDevice
		err := rows.Scan(
			&device.ID, &device.UserID, &device.DeviceFingerprint, &device.DeviceName,
			&device.DeviceType, &device.LastSeenAt, &device.IsActive, &device.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan device: %w", err)
		}
		devices = append(devices, device)
	}

	return devices, nil
}

// Helper function to generate random numeric code
func generateRandomCode(length int) string {
	code := make([]byte, length)
	for i := range code {
		digit, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			code[i] = '0'
			continue
		}
		code[i] = byte(digit.Int64()) + '0'
	}
	return string(code)
}
