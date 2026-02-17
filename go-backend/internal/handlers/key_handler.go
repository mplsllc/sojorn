package handlers

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

type KeyHandler struct {
	repo *repository.UserRepository
}

func NewKeyHandler(repo *repository.UserRepository) *KeyHandler {
	return &KeyHandler{repo: repo}
}

type PublishKeysRequest struct {
	IdentityKeyPublic     string          `json:"identity_key_public" binding:"required"`
	SignedPrekeyPublic    string          `json:"signed_prekey_public" binding:"required"`
	SignedPrekeyID        int             `json:"signed_prekey_id"`
	SignedPrekeySignature string          `json:"signed_prekey_signature"`
	OneTimePrekeys        json.RawMessage `json:"one_time_prekeys"`
	RegistrationID        int             `json:"registration_id" binding:"required"`
}

func (h *KeyHandler) PublishKeys(c *gin.Context) {
	fmt.Println("[KEYS] POST /api/v1/keys called - uploading key bundle")

	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	fmt.Printf("[KEYS] User ID: %s\n", userID.String())

	var req PublishKeysRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		fmt.Printf("[KEYS] ERROR: Failed to parse key bundle: %v\n", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Debug: Log OTK count
	fmt.Printf("[KEYS] Received bundle with %d OTKs\n", len(req.OneTimePrekeys))

	// CRITICAL: Log signature details
	fmt.Printf("[KEYS] Received SPK signature: %s\n", req.SignedPrekeySignature)
	fmt.Printf("[KEYS] SPK signature length: %d\n", len(req.SignedPrekeySignature))

	// Decode and verify signature is not all zeros
	sigBytes, err := base64.StdEncoding.DecodeString(req.SignedPrekeySignature)
	if err != nil {
		fmt.Printf("[KEYS] ERROR: Invalid signature encoding: %v\n", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid signature encoding"})
		return
	}

	fmt.Printf("[KEYS] Decoded signature length: %d bytes\n", len(sigBytes))
	if len(sigBytes) > 0 {
		fmt.Printf("[KEYS] Signature (first 16 bytes): %x\n", sigBytes[:int(math.Min(float64(16), float64(len(sigBytes))))])
	}

	allZeros := true
	for _, b := range sigBytes {
		if b != 0 {
			allZeros = false
			break
		}
	}

	if allZeros {
		fmt.Printf("[KEYS] ERROR: Signature is all zeros! Rejecting upload.\n")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid signature - all zeros"})
		return
	}

	fmt.Printf("[KEYS] Signature validation passed\n")

	err = h.repo.UpsertKeys(c.Request.Context(), userID.String(), repository.SignalKeysInput{
		IdentityKeyPublic:     req.IdentityKeyPublic,
		SignedPrekeyPublic:    req.SignedPrekeyPublic,
		SignedPrekeyID:        req.SignedPrekeyID,
		SignedPrekeySignature: req.SignedPrekeySignature,
		OneTimePrekeys:        req.OneTimePrekeys,
		RegistrationID:        req.RegistrationID,
	})

	if err != nil {
		fmt.Printf("[KEYS] ERROR: Failed to upsert keys for user %s: %v\n", userID.String(), err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update keys", "details": err.Error()})
		return
	}

	fmt.Println("[KEYS] Key bundle stored successfully")
	fmt.Printf("[KEYS] SUCCESS: Keys upserted for user %s\n", userID.String())

	c.JSON(http.StatusOK, gin.H{"message": "Keys published successfully"})
}

func (h *KeyHandler) DeleteUsedOTK(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	keyIDStr := c.Param("keyId")
	keyID, err := strconv.Atoi(keyIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid key ID"})
		return
	}

	err = h.repo.DeleteUsedOTK(c.Request.Context(), userID, keyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete OTK"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "OTK deleted successfully"})
}

func (h *KeyHandler) GetKeyBundle(c *gin.Context) {
	targetUserID := c.Param("id")
	fmt.Printf("[KEYS] GET request for user: %s\n", targetUserID)

	requesterID, exists := c.Get("user_id")
	if !exists {
		fmt.Println("[KEYS] ERROR: Unauthorized - no user_id in context")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	if targetUserID == "" {
		fmt.Println("[KEYS] ERROR: User ID required but not provided")
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	fmt.Printf("[KEYS] Fetching key bundle for user %s (requested by %s)\n", targetUserID, requesterID)

	bundle, err := h.repo.GetSignalKeyBundle(c.Request.Context(), targetUserID)
	if err != nil {
		fmt.Printf("[KEYS] ERROR: Key bundle not found for %s: %v\n", targetUserID, err)
		c.JSON(http.StatusNotFound, gin.H{"error": "Key bundle not found"})
		return
	}

	fmt.Printf("[KEYS] SUCCESS: Returning key bundle for user %s\n", targetUserID)
	c.JSON(http.StatusOK, bundle)
}
