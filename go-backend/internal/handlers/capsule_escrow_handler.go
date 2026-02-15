package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// CapsuleEscrowHandler handles capsule_keys (per-user encrypted group keys)
// and capsule_key_backups (PIN-encrypted private key escrow).
//
// SECURITY INVARIANT: Every query MUST filter by authenticated user_id.
// The server is a Zero-Knowledge store — it never decrypts any blob.
type CapsuleEscrowHandler struct {
	pool *pgxpool.Pool
}

func NewCapsuleEscrowHandler(pool *pgxpool.Pool) *CapsuleEscrowHandler {
	return &CapsuleEscrowHandler{pool: pool}
}

// ═════════════════════════════════════════════════════════════════════════════
// CAPSULE KEYS — Per-user encrypted group key blobs
// ═════════════════════════════════════════════════════════════════════════════

// GetMyKeys returns all capsule keys for the authenticated user.
func (h *CapsuleEscrowHandler) GetMyKeys(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	ctx := c.Request.Context()

	rows, err := h.pool.Query(ctx, `
		SELECT id, user_id, group_id, encrypted_key_blob, key_version, created_at, updated_at
		FROM capsule_keys
		WHERE user_id = $1
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch keys"})
		return
	}
	defer rows.Close()

	var keys []gin.H
	for rows.Next() {
		var id, uid, gid uuid.UUID
		var blob string
		var kv int
		var createdAt, updatedAt time.Time
		if err := rows.Scan(&id, &uid, &gid, &blob, &kv, &createdAt, &updatedAt); err != nil {
			continue
		}
		keys = append(keys, gin.H{
			"id": id, "user_id": uid, "group_id": gid,
			"encrypted_key_blob": blob, "key_version": kv,
			"created_at": createdAt, "updated_at": updatedAt,
		})
	}
	if keys == nil {
		keys = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"keys": keys})
}

// GetMyKeyForGroup returns the encrypted key blob for a specific group.
func (h *CapsuleEscrowHandler) GetMyKeyForGroup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	var id uuid.UUID
	var blob string
	var kv int
	var createdAt, updatedAt time.Time
	err = h.pool.QueryRow(c.Request.Context(), `
		SELECT id, encrypted_key_blob, key_version, created_at, updated_at
		FROM capsule_keys
		WHERE user_id = $1 AND group_id = $2
	`, userID, groupID).Scan(&id, &blob, &kv, &createdAt, &updatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "key not found for this group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"key": gin.H{
		"id": id, "user_id": userID, "group_id": groupID,
		"encrypted_key_blob": blob, "key_version": kv,
		"created_at": createdAt, "updated_at": updatedAt,
	}})
}

// StoreKey upserts an encrypted key blob for the authenticated user + group.
func (h *CapsuleEscrowHandler) StoreKey(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req struct {
		GroupID          string `json:"group_id"`
		EncryptedKeyBlob string `json:"encrypted_key_blob"`
		KeyVersion       int    `json:"key_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	groupID, err := uuid.Parse(req.GroupID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	if req.EncryptedKeyBlob == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "encrypted_key_blob required"})
		return
	}

	_, err = h.pool.Exec(c.Request.Context(), `
		INSERT INTO capsule_keys (user_id, group_id, encrypted_key_blob, key_version)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, group_id) DO UPDATE
		SET encrypted_key_blob = $3, key_version = $4, updated_at = NOW()
	`, userID, groupID, req.EncryptedKeyBlob, req.KeyVersion)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store key"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "stored"})
}

// DeleteKey removes a capsule key for the authenticated user (e.g. on leave).
func (h *CapsuleEscrowHandler) DeleteKey(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	_, err = h.pool.Exec(c.Request.Context(), `
		DELETE FROM capsule_keys WHERE user_id = $1 AND group_id = $2
	`, userID, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete key"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// ═════════════════════════════════════════════════════════════════════════════
// ESCROW BACKUP — PIN-encrypted private key recovery
// ═════════════════════════════════════════════════════════════════════════════

// UploadBackup stores the user's PIN-encrypted private key backup.
// The server treats this as an opaque blob — it cannot decrypt it.
func (h *CapsuleEscrowHandler) UploadBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req struct {
		Salt       string `json:"salt"`
		IV         string `json:"iv"`
		Payload    string `json:"payload"`
		PublicKey  string `json:"pub"`
		BackupType string `json:"backup_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Salt == "" || req.IV == "" || req.Payload == "" || req.PublicKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "salt, iv, payload, and pub are all required"})
		return
	}
	if req.BackupType == "" {
		req.BackupType = "passphrase"
	}

	_, err := h.pool.Exec(c.Request.Context(), `
		INSERT INTO capsule_key_backups (user_id, salt, iv, payload, public_key, backup_type)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id, backup_type) DO UPDATE
		SET salt = $2, iv = $3, payload = $4, public_key = $5, updated_at = NOW()
	`, userID, req.Salt, req.IV, req.Payload, req.PublicKey, req.BackupType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store backup"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "backup_stored"})
}

// GetBackup returns the user's encrypted backup blob.
// Accepts optional ?type=passphrase|recovery_key query param (defaults to passphrase).
func (h *CapsuleEscrowHandler) GetBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	backupType := c.DefaultQuery("type", "passphrase")

	var salt, iv, payload, pubKey string
	err := h.pool.QueryRow(c.Request.Context(), `
		SELECT salt, iv, payload, public_key
		FROM capsule_key_backups
		WHERE user_id = $1 AND backup_type = $2
	`, userID, backupType).Scan(&salt, &iv, &payload, &pubKey)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no backup found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"backup": gin.H{
			"salt":    salt,
			"iv":      iv,
			"payload": payload,
			"pub":     pubKey,
		},
	})
}

// GetBackupStatus returns whether a backup exists for the authenticated user.
func (h *CapsuleEscrowHandler) GetBackupStatus(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var exists bool
	h.pool.QueryRow(c.Request.Context(), `
		SELECT EXISTS(SELECT 1 FROM capsule_key_backups WHERE user_id = $1)
	`, userID).Scan(&exists)

	c.JSON(http.StatusOK, gin.H{"has_backup": exists})
}

// DeleteBackup removes the user's encrypted backup.
func (h *CapsuleEscrowHandler) DeleteBackup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	_, err := h.pool.Exec(c.Request.Context(), `
		DELETE FROM capsule_key_backups WHERE user_id = $1
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete backup"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "backup_deleted"})
}
