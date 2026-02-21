// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"crypto/rand"
	"encoding/base64"
	"math/big"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

type BackupHandler struct {
	repo *repository.BackupRepository
}

func NewBackupHandler(repo *repository.BackupRepository) *BackupHandler {
	return &BackupHandler{repo: repo}
}

// GenerateSyncCode generates a 6-digit code for device pairing
func (h *BackupHandler) GenerateSyncCode(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.GenerateSyncCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Generate 6-digit code
	code, err := h.repo.GenerateSyncCode(c.Request.Context(), userID, req.DeviceName, req.DeviceFingerprint)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to generate sync code"})
		return
	}

	c.JSON(200, models.GenerateSyncCodeResponse{
		Code:      code.Code,
		ExpiresAt: code.ExpiresAt,
		ExpiresIn: int(code.ExpiresAt.Sub(time.Now()).Seconds()),
	})
}

// VerifySyncCode verifies a sync code and initiates device pairing
func (h *BackupHandler) VerifySyncCode(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.VerifySyncCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Verify the sync code
	syncCode, err := h.repo.VerifySyncCode(
		c.Request.Context(),
		req.Code,
		userID,
		userID,
		req.DeviceName,
		req.DeviceFingerprint,
	)
	if err != nil {
		if strings.Contains(err.Error(), "expired") {
			c.JSON(400, models.VerifySyncCodeResponse{
				Valid:       false,
				ErrorMessage: "Sync code has expired",
			})
		} else if strings.Contains(err.Error(), "invalid") {
			c.JSON(400, models.VerifySyncCodeResponse{
				Valid:       false,
				ErrorMessage: "Invalid sync code",
			})
		} else if strings.Contains(err.Error(), "attempts") {
			c.JSON(429, models.VerifySyncCodeResponse{
				Valid:       false,
				ErrorMessage: "Too many attempts. Please generate a new code.",
			})
		} else {
			c.JSON(500, gin.H{"error": "Failed to verify sync code"})
		}
		return
	}

	// Register the new device
	_, err = h.repo.RegisterDevice(c.Request.Context(), userID, req.DeviceName, req.DeviceFingerprint, "web")
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to register device"})
		return
	}

	c.JSON(200, models.VerifySyncCodeResponse{
		Valid:       true,
		DeviceAID:   syncCode.UserID.String(),
		DeviceAName: syncCode.DeviceName,
		// WebRTCOffer would be generated here in a real implementation
	})
}

// UploadBackup uploads an encrypted backup to cloud storage
func (h *BackupHandler) UploadBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.UploadBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Decode base64 data
	encryptedBlob, err := base64.StdEncoding.DecodeString(req.EncryptedBlob)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid encrypted blob encoding"})
		return
	}

	salt, err := base64.StdEncoding.DecodeString(req.Salt)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid salt encoding"})
		return
	}

	nonce, err := base64.StdEncoding.DecodeString(req.Nonce)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid nonce encoding"})
		return
	}

	mac, err := base64.StdEncoding.DecodeString(req.Mac)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid MAC encoding"})
		return
	}

	// Create backup record
	backup := &models.CloudBackup{
		UserID:        userID,
		EncryptedBlob: encryptedBlob,
		Salt:          salt,
		Nonce:         nonce,
		Mac:           mac,
		Version:       req.Version,
		DeviceName:    req.DeviceName,
		SizeBytes:     int64(len(encryptedBlob)),
	}

	backupID, err := h.repo.UploadBackup(c.Request.Context(), backup)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to upload backup"})
		return
	}

	// Update last backup time
	h.repo.UpdateLastBackupTime(c.Request.Context(), userID)

	c.JSON(200, models.UploadBackupResponse{
		BackupID:   backupID.String(),
		UploadedAt: time.Now(),
		Size:       backup.SizeBytes,
	})
}

// DownloadBackup downloads an encrypted backup from cloud storage
func (h *BackupHandler) DownloadBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	backupID := c.Param("backup_id")
	if backupID == "" {
		// If no specific backup ID, get the latest
		backup, err := h.repo.GetLatestBackup(c.Request.Context(), userID)
		if err != nil {
			c.JSON(404, gin.H{"error": "No backup found"})
			return
		}

		c.JSON(200, models.DownloadBackupResponse{
			EncryptedBlob: base64.StdEncoding.EncodeToString(backup.EncryptedBlob),
			Salt:          base64.StdEncoding.EncodeToString(backup.Salt),
			Nonce:         base64.StdEncoding.EncodeToString(backup.Nonce),
			Mac:           base64.StdEncoding.EncodeToString(backup.Mac),
			Version:       backup.Version,
			DeviceName:    backup.DeviceName,
			CreatedAt:     backup.CreatedAt,
		})
		return
	}

	// Get specific backup
	backupUUID, err := uuid.Parse(backupID)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid backup ID"})
		return
	}

	backup, err := h.repo.GetBackup(c.Request.Context(), backupUUID, userID)
	if err != nil {
		c.JSON(404, gin.H{"error": "Backup not found"})
		return
	}

	c.JSON(200, models.DownloadBackupResponse{
		EncryptedBlob: base64.StdEncoding.EncodeToString(backup.EncryptedBlob),
		Salt:          base64.StdEncoding.EncodeToString(backup.Salt),
		Nonce:         base64.StdEncoding.EncodeToString(backup.Nonce),
		Mac:           base64.StdEncoding.EncodeToString(backup.Mac),
		Version:       backup.Version,
		DeviceName:    backup.DeviceName,
		CreatedAt:     backup.CreatedAt,
	})
}

// ListBackups lists all available backups for a user
func (h *BackupHandler) ListBackups(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	backups, err := h.repo.ListBackups(c.Request.Context(), userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to list backups"})
		return
	}

	c.JSON(200, models.ListBackupsResponse{
		Backups: backups,
	})
}

// DeleteBackup deletes a specific backup
func (h *BackupHandler) DeleteBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	backupID := c.Param("backup_id")
	backupUUID, err := uuid.Parse(backupID)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid backup ID"})
		return
	}

	err = h.repo.DeleteBackup(c.Request.Context(), backupUUID, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to delete backup"})
		return
	}

	c.JSON(200, gin.H{"message": "Backup deleted successfully"})
}

// SetupSocialRecovery sets up social recovery with trusted guardians
func (h *BackupHandler) SetupSocialRecovery(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.SetupSocialRecoveryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Validate guardian count
	if len(req.GuardianUserIDs) < 3 || len(req.GuardianUserIDs) > 5 {
		c.JSON(400, gin.H{"error": "Must have between 3 and 5 guardians"})
		return
	}

	// Convert string IDs to UUIDs
	guardianIDs := make([]uuid.UUID, len(req.GuardianUserIDs))
	for i, idStr := range req.GuardianUserIDs {
		id, err := uuid.Parse(idStr)
		if err != nil {
			c.JSON(400, gin.H{"error": "Invalid guardian user ID"})
			return
		}
		guardianIDs[i] = id
	}

	// Generate master secret and split into shards
	masterSecret := make([]byte, 32)
	if _, err := rand.Read(masterSecret); err != nil {
		c.JSON(500, gin.H{"error": "Failed to generate master secret"})
		return
	}

	// For now, we'll store the master secret encrypted with user's keys
	// In a real implementation, you'd use Shamir's Secret Sharing
	err := h.repo.SetupSocialRecovery(c.Request.Context(), userID, guardianIDs, masterSecret)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to setup social recovery"})
		return
	}

	c.JSON(200, gin.H{"message": "Social recovery setup complete"})
}

// InitiateRecovery starts a recovery session
func (h *BackupHandler) InitiateRecovery(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.InitiateRecoveryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	session, err := h.repo.InitiateRecovery(c.Request.Context(), userID, req.Method)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to initiate recovery"})
		return
	}

	c.JSON(200, session)
}

// SubmitShard submits a recovery shard from a guardian
func (h *BackupHandler) SubmitShard(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.SubmitShardRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	sessionUUID, err := uuid.Parse(req.SessionID)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid session ID"})
		return
	}

	// Decode base64 shard
	shardEncrypted, err := base64.StdEncoding.DecodeString(req.ShardEncrypted)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid shard encoding"})
		return
	}

	submission, err := h.repo.SubmitShard(c.Request.Context(), sessionUUID, userID, shardEncrypted)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to submit shard"})
		return
	}

	c.JSON(200, models.SubmitShardResponse{
		ShardsReceived: submission.ShardsReceived,
		ShardsNeeded:   submission.ShardsNeeded,
		CanComplete:    submission.ShardsReceived >= submission.ShardsNeeded,
	})
}

// CompleteRecovery attempts to complete the recovery process
func (h *BackupHandler) CompleteRecovery(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	sessionID := c.Param("session_id")
	sessionUUID, err := uuid.Parse(sessionID)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid session ID"})
		return
	}

	masterKey, err := h.repo.CompleteRecovery(c.Request.Context(), sessionUUID, userID)
	if err != nil {
		if strings.Contains(err.Error(), "insufficient") {
			c.JSON(400, models.CompleteRecoveryResponse{
				Success:      false,
				ErrorMessage: "Insufficient shards to complete recovery",
			})
		} else {
			c.JSON(500, models.CompleteRecoveryResponse{
				Success:      false,
				ErrorMessage: "Failed to complete recovery",
			})
		}
		return
	}

	c.JSON(200, models.CompleteRecoveryResponse{
		Success:   true,
		MasterKey: base64.StdEncoding.EncodeToString(masterKey),
	})
}

// GetBackupPreferences gets user's backup preferences
func (h *BackupHandler) GetBackupPreferences(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	preferences, err := h.repo.GetBackupPreferences(c.Request.Context(), userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get backup preferences"})
		return
	}

	c.JSON(200, preferences)
}

// UpdateBackupPreferences updates user's backup preferences
func (h *BackupHandler) UpdateBackupPreferences(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.UpdateBackupPreferencesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	err := h.repo.UpdateBackupPreferences(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to update backup preferences"})
		return
	}

	c.JSON(200, gin.H{"message": "Backup preferences updated"})
}

// GetUserDevices gets all registered devices for a user
func (h *BackupHandler) GetUserDevices(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	devices, err := h.repo.GetUserDevices(c.Request.Context(), userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get user devices"})
		return
	}

	c.JSON(200, gin.H{"devices": devices})
}

// Helper function to generate random 6-digit code
func generateSyncCode() string {
	code := make([]byte, 6)
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
