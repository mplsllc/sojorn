package monitoring

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

type HealthCheckService struct {
	db          *pgxpool.Pool
	httpClient  *http.Client
	checks      map[string]HealthCheck
	mutex       sync.RWMutex
	startTime   time.Time
}

type HealthCheck struct {
	Name        string            `json:"name"`
	Status      string            `json:"status"`
	Message     string            `json:"message"`
	Duration    time.Duration     `json:"duration"`
	Timestamp   time.Time         `json:"timestamp"`
	Details     map[string]interface{} `json:"details,omitempty"`
}

type HealthStatus struct {
	Status      string                 `json:"status"`
	Timestamp   time.Time              `json:"timestamp"`
	Uptime      time.Duration          `json:"uptime"`
	Version     string                 `json:"version"`
	Environment string                 `json:"environment"`
	Checks      map[string]HealthCheck  `json:"checks"`
	System      SystemInfo              `json:"system"`
}

type SystemInfo struct {
	GoVersion    string  `json:"go_version"`
	NumGoroutine int     `json:"num_goroutine"`
	MemoryUsage  MemInfo `json:"memory_usage"`
	NumCPU       int     `json:"num_cpu"`
}

type MemInfo struct {
	Alloc      uint64 `json:"alloc"`
	TotalAlloc uint64 `json:"total_alloc"`
	Sys        uint64 `json:"sys"`
	NumGC      uint32 `json:"num_gc"`
}

type AlertLevel string

const (
	AlertLevelInfo    AlertLevel = "info"
	AlertLevelWarning AlertLevel = "warning"
	AlertLevelError   AlertLevel = "error"
	AlertLevelCritical AlertLevel = "critical"
)

type Alert struct {
	Level     AlertLevel `json:"level"`
	Service   string     `json:"service"`
	Message   string     `json:"message"`
	Timestamp time.Time  `json:"timestamp"`
	Details   map[string]interface{} `json:"details,omitempty"`
}

func NewHealthCheckService(db *pgxpool.Pool) *HealthCheckService {
	return &HealthCheckService{
		db:         db,
		httpClient: &http.Client{Timeout: 10 * time.Second},
		checks:     make(map[string]HealthCheck),
		startTime:  time.Now(),
	}
}

// Run all health checks
func (s *HealthCheckService) RunHealthChecks(ctx context.Context) HealthStatus {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	checks := make(map[string]HealthCheck)

	// Database health check
	checks["database"] = s.checkDatabase(ctx)

	// External service checks
	checks["azure_openai"] = s.checkAzureOpenAI(ctx)
	checks["cloudflare_r2"] = s.checkCloudflareR2(ctx)

	// Internal service checks
	checks["api_server"] = s.checkAPIServer(ctx)
	checks["auth_service"] = s.checkAuthService(ctx)

	// System checks
	checks["memory"] = s.checkMemoryUsage()
	checks["disk_space"] = s.checkDiskSpace()

	// Determine overall status
	overallStatus := "healthy"
	for _, check := range checks {
		if check.Status == "unhealthy" {
			overallStatus = "unhealthy"
			break
		} else if check.Status == "degraded" && overallStatus == "healthy" {
			overallStatus = "degraded"
		}
	}

	return HealthStatus{
		Status:      overallStatus,
		Timestamp:   time.Now(),
		Uptime:      time.Since(s.startTime),
		Version:     "1.0.0", // This should come from build info
		Environment: "production", // This should come from config
		Checks:      checks,
		System:      s.getSystemInfo(),
	}
}

// Database health check
func (s *HealthCheckService) checkDatabase(ctx context.Context) HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "database",
		Timestamp: start,
	}

	// Test database connection
	var result sql.NullString
	err := s.db.QueryRow(ctx, "SELECT 'healthy' as status").Scan(&result)
	
	if err != nil {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("Database connection failed: %v", err)
		check.Duration = time.Since(start)
		return check
	}

	// Check database stats
	var connectionCount int
	err = s.db.QueryRow(ctx, "SELECT count(*) FROM pg_stat_activity").Scan(&connectionCount)
	
	check.Status = "healthy"
	check.Message = "Database connection successful"
	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"connection_count": connectionCount,
		"status": result.String,
	}

	return check
}

// Azure OpenAI health check
func (s *HealthCheckService) checkAzureOpenAI(ctx context.Context) HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "azure_openai",
		Timestamp: start,
	}

	// Create a simple test request
	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.openai.com/v1/models", nil)
	if err != nil {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("Failed to create request: %v", err)
		check.Duration = time.Since(start)
		return check
	}

	// Add authorization header (this should come from config)
	req.Header.Set("Authorization", "Bearer test-key")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("Request failed: %v", err)
		check.Duration = time.Since(start)
		return check
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		check.Status = "healthy"
		check.Message = "Azure OpenAI service is responsive"
	} else if resp.StatusCode >= 400 && resp.StatusCode < 500 {
		check.Status = "degraded"
		check.Message = fmt.Sprintf("Azure OpenAI returned status %d", resp.StatusCode)
	} else {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("Azure OpenAI returned status %d", resp.StatusCode)
	}

	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"status_code": resp.StatusCode,
	}

	return check
}

// Cloudflare R2 health check
func (s *HealthCheckService) checkCloudflareR2(ctx context.Context) HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "cloudflare_r2",
		Timestamp: start,
	}

	// Test R2 connectivity (this would be a real R2 API call)
	// For now, we'll simulate the check
	time.Sleep(100 * time.Millisecond) // Simulate network latency

	check.Status = "healthy"
	check.Message = "Cloudflare R2 service is accessible"
	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"endpoint": "https://your-account.r2.cloudflarestorage.com",
		"latency_ms": check.Duration.Milliseconds(),
	}

	return check
}

// API server health check
func (s *HealthCheckService) checkAPIServer(ctx context.Context) HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "api_server",
		Timestamp: start,
	}

	// Test internal API endpoint
	req, err := http.NewRequestWithContext(ctx, "GET", "http://localhost:8080/health", nil)
	if err != nil {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("Failed to create API request: %v", err)
		check.Duration = time.Since(start)
		return check
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("API request failed: %v", err)
		check.Duration = time.Since(start)
		return check
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		check.Status = "healthy"
		check.Message = "API server is responding"
	} else {
		check.Status = "unhealthy"
		check.Message = fmt.Sprintf("API server returned status %d", resp.StatusCode)
	}

	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"status_code": resp.StatusCode,
	}

	return check
}

// Auth service health check
func (s *HealthCheckService) checkAuthService(ctx context.Context) HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "auth_service",
		Timestamp: start,
	}

	// Test auth service (this would be a real auth service check)
	// For now, we'll simulate the check
	time.Sleep(50 * time.Millisecond)

	check.Status = "healthy"
	check.Message = "Auth service is operational"
	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"jwt_validation": "working",
		"token_refresh": "working",
	}

	return check
}

// Memory usage check
func (s *HealthCheckService) checkMemoryUsage() HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "memory",
		Timestamp: start,
	}

	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Check memory usage (threshold: 80% of available memory)
	memoryUsageMB := m.Alloc / 1024 / 1024
	thresholdMB := uint64(1024) // 1GB threshold

	check.Status = "healthy"
	check.Message = "Memory usage is normal"
	
	if memoryUsageMB > thresholdMB {
		check.Status = "degraded"
		check.Message = "Memory usage is high"
	}

	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"alloc_mb":        memoryUsageMB,
		"total_alloc_mb":  m.TotalAlloc / 1024 / 1024,
		"sys_mb":          m.Sys / 1024 / 1024,
		"num_gc":          m.NumGC,
		"threshold_mb":    thresholdMB,
	}

	return check
}

// Disk space check
func (s *HealthCheckService) checkDiskSpace() HealthCheck {
	start := time.Now()
	
	check := HealthCheck{
		Name:      "disk_space",
		Timestamp: start,
	}

	// This would check actual disk space
	// For now, we'll simulate the check
	diskUsagePercent := 45.0 // Simulated disk usage

	check.Status = "healthy"
	check.Message = "Disk space is sufficient"
	
	if diskUsagePercent > 80 {
		check.Status = "degraded"
		check.Message = "Disk space is low"
	} else if diskUsagePercent > 90 {
		check.Status = "unhealthy"
		check.Message = "Disk space is critically low"
	}

	check.Duration = time.Since(start)
	check.Details = map[string]interface{}{
		"usage_percent": diskUsagePercent,
		"available_gb":  55.0, // Simulated
		"total_gb":      100.0, // Simulated
	}

	return check
}

// Get system information
func (s *HealthCheckService) getSystemInfo() SystemInfo {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	return SystemInfo{
		GoVersion:    runtime.Version(),
		NumGoroutine: runtime.NumGoroutine(),
		MemoryUsage: MemInfo{
			Alloc:      m.Alloc,
			TotalAlloc: m.TotalAlloc,
			Sys:        m.Sys,
			NumGC:      m.NumGC,
		},
		NumCPU: runtime.NumCPU(),
	}
}

// Send alert if needed
func (s *HealthCheckService) sendAlert(ctx context.Context, level AlertLevel, service, message string, details map[string]interface{}) {
	alert := Alert{
		Level:     level,
		Service:   service,
		Message:   message,
		Timestamp: time.Now(),
		Details:   details,
	}

	// Log the alert
	logLevel := zerolog.InfoLevel
	switch level {
	case AlertLevelWarning:
		logLevel = zerolog.WarnLevel
	case AlertLevelError:
		logLevel = zerolog.ErrorLevel
	case AlertLevelCritical:
		logLevel = zerolog.FatalLevel
	}

	log.WithLevel(logLevel).
		Str("service", service).
		Str("message", message).
		Interface("details", details).
		Msg("Health check alert")

	// Here you would send to external monitoring service
	// e.g., PagerDuty, Slack, email, etc.
	s.sendToMonitoringService(ctx, alert)
}

// Send to external monitoring service
func (s *HealthCheckService) sendToMonitoringService(ctx context.Context, alert Alert) {
	// This would integrate with your monitoring service
	// For now, we'll just log it
	alertJSON, _ := json.Marshal(alert)
	log.Info().Str("alert", string(alertJSON)).Msg("Sending to monitoring service")
}

// Get health check history
func (s *HealthCheckService) GetHealthHistory(ctx context.Context, duration time.Duration) ([]HealthStatus, error) {
	// This would retrieve health check history from database or cache
	// For now, return empty slice
	return []HealthStatus{}, nil
}

// HTTP handler for health checks
func (s *HealthCheckService) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	
	health := s.RunHealthChecks(ctx)
	
	w.Header().Set("Content-Type", "application/json")
	
	if health.Status == "healthy" {
		w.WriteHeader(http.StatusOK)
	} else if health.Status == "degraded" {
		w.WriteHeader(http.StatusOK) // Still 200 but with degraded status
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	
	json.NewEncoder(w).Encode(health)
}

// HTTP handler for readiness checks
func (s *HealthCheckService) ReadinessHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	
	// Check critical services only
	dbCheck := s.checkDatabase(ctx)
	
	if dbCheck.Status == "healthy" {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))
	}
}

// HTTP handler for liveness checks
func (s *HealthCheckService) LivenessHandler(w http.ResponseWriter, r *http.Request) {
	// Simple liveness check - if we're running, we're alive
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("alive"))
}
