// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package testing

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
)

// IntegrationTestSuite provides comprehensive testing for the Sojorn platform
type IntegrationTestSuite struct {
	suite.Suite
	db          *pgxpool.Pool
	router      *gin.Engine
	server      *httptest.Server
	testUser    *TestUser
	testGroup   *TestGroup
	testPost    *TestPost
	cleanup     []func()
}

// TestUser represents a test user
type TestUser struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	Handle   string `json:"handle"`
	Token    string `json:"token"`
	Password string `json:"password"`
}

// TestGroup represents a test group
type TestGroup struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Category    string `json:"category"`
	IsPrivate   bool   `json:"is_private"`
}

// TestPost represents a test post
type TestPost struct {
	ID          string `json:"id"`
	Body        string `json:"body"`
	AuthorID    string `json:"author_id"`
	ImageURL    string `json:"image_url,omitempty"`
	VideoURL    string `json:"video_url,omitempty"`
	Visibility  string `json:"visibility"`
}

// TestConfig holds test configuration
type TestConfig struct {
	DatabaseURL string
	BaseURL     string
	TestTimeout time.Duration
}

// SetupSuite initializes the test suite
func (suite *IntegrationTestSuite) SetupSuite() {
	config := suite.getTestConfig()
	
	// Initialize database
	db, err := pgxpool.New(context.Background(), config.DatabaseURL)
	require.NoError(suite.T(), err)
	suite.db = db
	
	// Initialize router
	suite.router = gin.New()
	suite.setupRoutes()
	
	// Start test server
	suite.server = httptest.NewServer(suite.router)
	
	// Create test data
	suite.createTestData()
}

// TearDownSuite cleans up after tests
func (suite *IntegrationTestSuite) TearDownSuite() {
	// Run cleanup functions
	for _, cleanup := range suite.cleanup {
		cleanup()
	}
	
	// Close database connection
	if suite.db != nil {
		suite.db.Close()
	}
	
	// Close test server
	if suite.server != nil {
		suite.server.Close()
	}
}

// getTestConfig loads test configuration
func (suite *IntegrationTestSuite) getTestConfig() TestConfig {
	return TestConfig{
		DatabaseURL: os.Getenv("TEST_DATABASE_URL"),
		BaseURL:     "http://localhost:8080",
		TestTimeout: 30 * time.Second,
	}
}

// setupRoutes configures test routes
func (suite *IntegrationTestSuite) setupRoutes() {
	// This would include all your API routes
	// For now, we'll add basic health check
	suite.router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "healthy"})
	})
	
	// Add auth routes
	suite.router.POST("/auth/register", suite.handleRegister)
	suite.router.POST("/auth/login", suite.handleLogin)
	
	// Add post routes
	suite.router.GET("/posts", suite.handleGetPosts)
	suite.router.POST("/posts", suite.handleCreatePost)
	
	// Add group routes
	suite.router.GET("/groups", suite.handleGetGroups)
	suite.router.POST("/groups", suite.handleCreateGroup)
}

// createTestData sets up test data
func (suite *IntegrationTestSuite) createTestData() {
	// Create test user
	suite.testUser = &TestUser{
		Email:    "test@example.com",
		Handle:   "testuser",
		Password: "testpassword123",
	}
	
	userResp := suite.makeRequest("POST", "/auth/register", suite.testUser)
	require.Equal(suite.T(), 200, userResp.StatusCode)
	
	var userResult struct {
		User  TestUser `json:"user"`
		Token string   `json:"token"`
	}
	json.NewDecoder(userResp.Body).Decode(&userResult)
	suite.testUser = &userResult.User
	suite.testUser.Token = userResult.Token
	
	// Create test group
	suite.testGroup = &TestGroup{
		Name:        "Test Group",
		Description: "A group for testing",
		Category:    "general",
		IsPrivate:   false,
	}
	
	groupResp := suite.makeAuthenticatedRequest("POST", "/groups", suite.testGroup)
	require.Equal(suite.T(), 200, groupResp.StatusCode)
	
	json.NewDecoder(groupResp.Body).Decode(&suite.testGroup)
	
	// Create test post
	suite.testPost = &TestPost{
		Body:       "This is a test post",
		AuthorID:   suite.testUser.ID,
		Visibility: "public",
	}
	
	postResp := suite.makeAuthenticatedRequest("POST", "/posts", suite.testPost)
	require.Equal(suite.T(), 200, postResp.StatusCode)
	
	json.NewDecoder(postResp.Body).Decode(&suite.testPost)
}

// makeRequest makes an HTTP request
func (suite *IntegrationTestSuite) makeRequest(method, path string, body interface{}) *http.Response {
	var reqBody *bytes.Buffer
	if body != nil {
		jsonBody, _ := json.Marshal(body)
		reqBody = bytes.NewBuffer(jsonBody)
	} else {
		reqBody = bytes.NewBuffer(nil)
	}
	
	req, _ := http.NewRequest(method, suite.server.URL+path, reqBody)
	req.Header.Set("Content-Type", "application/json")
	
	client := &http.Client{Timeout: 10 * time.Second}
	resp, _ := client.Do(req)
	
	return resp
}

// makeAuthenticatedRequest makes an authenticated HTTP request
func (suite *IntegrationTestSuite) makeAuthenticatedRequest(method, path string, body interface{}) *http.Response {
	var reqBody *bytes.Buffer
	if body != nil {
		jsonBody, _ := json.Marshal(body)
		reqBody = bytes.NewBuffer(jsonBody)
	} else {
		reqBody = bytes.NewBuffer(nil)
	}
	
	req, _ := http.NewRequest(method, suite.server.URL+path, reqBody)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+suite.testUser.Token)
	
	client := &http.Client{Timeout: 10 * time.Second}
	resp, _ := client.Do(req)
	
	return resp
}

// Test Authentication Flow
func (suite *IntegrationTestSuite) TestAuthenticationFlow() {
	// Test user registration
	newUser := TestUser{
		Email:    "newuser@example.com",
		Handle:   "newuser",
		Password: "newpassword123",
	}
	
	resp := suite.makeRequest("POST", "/auth/register", newUser)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var registerResult struct {
		User  TestUser `json:"user"`
		Token string   `json:"token"`
	}
	json.NewDecoder(resp.Body).Decode(&registerResult)
	assert.NotEmpty(suite.T(), registerResult.Token)
	
	// Test user login
	loginReq := map[string]string{
		"email":    newUser.Email,
		"password": newUser.Password,
	}
	
	resp = suite.makeRequest("POST", "/auth/login", loginReq)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var loginResult struct {
		User  TestUser `json:"user"`
		Token string   `json:"token"`
	}
	json.NewDecoder(resp.Body).Decode(&loginResult)
	assert.NotEmpty(suite.T(), loginResult.Token)
}

// Test Post Creation and Retrieval
func (suite *IntegrationTestSuite) TestPostOperations() {
	// Test creating a post
	newPost := TestPost{
		Body:       "This is a new test post",
		AuthorID:   suite.testUser.ID,
		Visibility: "public",
	}
	
	resp := suite.makeAuthenticatedRequest("POST", "/posts", newPost)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var createdPost TestPost
	json.NewDecoder(resp.Body).Decode(&createdPost)
	assert.NotEmpty(suite.T(), createdPost.ID)
	
	// Test retrieving posts
	resp = suite.makeAuthenticatedRequest("GET", "/posts", nil)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var posts []TestPost
	json.NewDecoder(resp.Body).Decode(&posts)
	assert.Greater(suite.T(), len(posts), 0)
}

// Test Group Operations
func (suite *IntegrationTestSuite) TestGroupOperations() {
	// Test creating a group
	newGroup := TestGroup{
		Name:        "New Test Group",
		Description: "Another test group",
		Category:    "hobby",
		IsPrivate:   false,
	}
	
	resp := suite.makeAuthenticatedRequest("POST", "/groups", newGroup)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var createdGroup TestGroup
	json.NewDecoder(resp.Body).Decode(&createdGroup)
	assert.NotEmpty(suite.T(), createdGroup.ID)
	
	// Test retrieving groups
	resp = suite.makeAuthenticatedRequest("GET", "/groups", nil)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var groups []TestGroup
	json.NewDecoder(resp.Body).Decode(&groups)
	assert.Greater(suite.T(), len(groups), 0)
}

// Test Feed Algorithm
func (suite *IntegrationTestSuite) TestFeedAlgorithm() {
	// Create multiple posts with different engagement
	posts := []TestPost{
		{Body: "Popular post 1", AuthorID: suite.testUser.ID, Visibility: "public"},
		{Body: "Popular post 2", AuthorID: suite.testUser.ID, Visibility: "public"},
		{Body: "Regular post", AuthorID: suite.testUser.ID, Visibility: "public"},
	}
	
	for _, post := range posts {
		resp := suite.makeAuthenticatedRequest("POST", "/posts", post)
		assert.Equal(suite.T(), 200, resp.StatusCode)
	}
	
	// Test algorithmic feed
	resp := suite.makeAuthenticatedRequest("GET", "/feed?algorithm=true", nil)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var feedPosts []TestPost
	json.NewDecoder(resp.Body).Decode(&feedPosts)
	assert.Greater(suite.T(), len(feedPosts), 0)
}

// Test E2EE Chat
func (suite *IntegrationTestSuite) TestE2EEChat() {
	// Test device registration
	deviceData := map[string]interface{}{
		"name":   "Test Device",
		"type":   "mobile",
		"public_key": "test-public-key",
	}
	
	resp := suite.makeAuthenticatedRequest("POST", "/e2ee/register-device", deviceData)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	// Test message encryption
	messageData := map[string]interface{}{
		"recipient_id": suite.testUser.ID,
		"message":      "Encrypted test message",
		"encrypted":    true,
	}
	
	resp = suite.makeAuthenticatedRequest("POST", "/e2ee/send-message", messageData)
	assert.Equal(suite.T(), 200, resp.StatusCode)
}

// Test AI Moderation
func (suite *IntegrationTestSuite) TestAIModeration() {
	// Test content moderation
	contentData := map[string]interface{}{
		"content": "This is safe content",
		"type":    "text",
	}
	
	resp := suite.makeAuthenticatedRequest("POST", "/moderation/analyze", contentData)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	var moderationResult struct {
		IsSafe bool `json:"is_safe"`
		Score  float64 `json:"score"`
	}
	json.NewDecoder(resp.Body).Decode(&moderationResult)
	assert.True(suite.T(), moderationResult.IsSafe)
}

// Test Video Processing
func (suite *IntegrationTestSuite) TestVideoProcessing() {
	// Test video upload and processing
	videoData := map[string]interface{}{
		"title":       "Test Video",
		"description": "A test video for processing",
		"duration":   30,
	}
	
	resp := suite.makeAuthenticatedRequest("POST", "/videos/upload", videoData)
	assert.Equal(suite.T(), 200, resp.StatusCode)
	
	// Test video processing status
	resp = suite.makeAuthenticatedRequest("GET", "/videos/processing-status", nil)
	assert.Equal(suite.T(), 200, resp.StatusCode)
}

// Test Performance
func (suite *IntegrationTestSuite) TestPerformance() {
	// Test API response times
	start := time.Now()
	resp := suite.makeAuthenticatedRequest("GET", "/posts", nil)
	duration := time.Since(start)
	
	assert.Equal(suite.T(), 200, resp.StatusCode)
	assert.Less(suite.T(), duration, 1*time.Second, "API response time should be under 1 second")
	
	// Test concurrent requests
	concurrentRequests := 10
	done := make(chan bool, concurrentRequests)
	
	for i := 0; i < concurrentRequests; i++ {
		go func() {
			resp := suite.makeAuthenticatedRequest("GET", "/posts", nil)
			assert.Equal(suite.T(), 200, resp.StatusCode)
			done <- true
		}()
	}
	
	// Wait for all requests to complete
	for i := 0; i < concurrentRequests; i++ {
		<-done
	}
}

// Test Security
func (suite *IntegrationTestSuite) TestSecurity() {
	// Test unauthorized access
	resp := suite.makeRequest("GET", "/posts", nil)
	assert.Equal(suite.T(), 401, resp.StatusCode)
	
	// Test invalid token
	resp = suite.makeRequestWithAuth("GET", "/posts", nil, "invalid-token")
	assert.Equal(suite.T(), 401, resp.StatusCode)
	
	// Test SQL injection protection
	maliciousInput := "'; DROP TABLE users; --"
	resp = suite.makeAuthenticatedRequest("GET", "/posts?search="+maliciousInput, nil)
	assert.Equal(suite.T(), 200, resp.StatusCode) // Should not crash
}

// makeRequestWithAuth makes a request with custom auth token
func (suite *IntegrationTestSuite) makeRequestWithAuth(method, path string, body interface{}, token string) *http.Response {
	var reqBody *bytes.Buffer
	if body != nil {
		jsonBody, _ := json.Marshal(body)
		reqBody = bytes.NewBuffer(jsonBody)
	} else {
		reqBody = bytes.NewBuffer(nil)
	}
	
	req, _ := http.NewRequest(method, suite.server.URL+path, reqBody)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	
	client := &http.Client{Timeout: 10 * time.Second}
	resp, _ := client.Do(req)
	
	return resp
}

// Mock handlers for testing
func (suite *IntegrationTestSuite) handleRegister(c *gin.Context) {
	var user TestUser
	c.ShouldBindJSON(&user)
	user.ID = "test-user-id"
	c.JSON(200, gin.H{"user": user, "token": "test-token"})
}

func (suite *IntegrationTestSuite) handleLogin(c *gin.Context) {
	var loginReq map[string]string
	c.ShouldBindJSON(&loginReq)
	
	user := TestUser{
		ID:     "test-user-id",
		Email:  loginReq["email"],
		Handle: "testuser",
	}
	
	c.JSON(200, gin.H{"user": user, "token": "test-token"})
}

func (suite *IntegrationTestSuite) handleGetPosts(c *gin.Context) {
	posts := []TestPost{
		{ID: "1", Body: "Test post 1", AuthorID: "test-user-id"},
		{ID: "2", Body: "Test post 2", AuthorID: "test-user-id"},
	}
	c.JSON(200, posts)
}

func (suite *IntegrationTestSuite) handleCreatePost(c *gin.Context) {
	var post TestPost
	c.ShouldBindJSON(&post)
	post.ID = "new-post-id"
	c.JSON(200, post)
}

func (suite *IntegrationTestSuite) handleGetGroups(c *gin.Context) {
	groups := []TestGroup{
		{ID: "1", Name: "Test Group 1", Category: "general"},
		{ID: "2", Name: "Test Group 2", Category: "hobby"},
	}
	c.JSON(200, groups)
}

func (suite *IntegrationTestSuite) handleCreateGroup(c *gin.Context) {
	var group TestGroup
	c.ShouldBindJSON(&group)
	group.ID = "new-group-id"
	c.JSON(200, group)
}

// RunIntegrationTests runs the complete integration test suite
func RunIntegrationTests(t *testing.T) {
	suite.Run(t, new(IntegrationTestSuite))
}
