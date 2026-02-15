package middleware

import (
	"net"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
)

// SimpleGeoBlockMiddleware blocks requests from known problematic regions using simple IP ranges
type SimpleGeoBlockMiddleware struct{}

// NewSimpleGeoBlockMiddleware creates a new simple geographic blocking middleware
func NewSimpleGeoBlockMiddleware() *SimpleGeoBlockMiddleware {
	return &SimpleGeoBlockMiddleware{}
}

// Middleware returns the Gin middleware function
func (g *SimpleGeoBlockMiddleware) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get client IP
		clientIP := c.ClientIP()

		// Parse IP
		ip := net.ParseIP(clientIP)
		if ip == nil {
			// Invalid IP, block it
			log.Warn().Str("ip", clientIP).Msg("Invalid IP address, blocking request")
			c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
			c.Abort()
			return
		}

		// Skip for private/local IPs
		if ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
			c.Next()
			return
		}

		// Simple blocking based on IP ranges for known problematic regions
		// This is a basic implementation - you can expand these ranges as needed
		if g.isBlockedIP(ip) {
			log.Info().Str("ip", clientIP).Msg("Blocking request from known problematic region")
			c.JSON(http.StatusForbidden, gin.H{"error": "Access denied - region not supported"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// isBlockedIP checks if the IP falls into known problematic ranges
func (g *SimpleGeoBlockMiddleware) isBlockedIP(ip net.IP) bool {
	// Block common bot/scanner IP ranges
	blockedRanges := []string{
		// Chinese IP ranges (simplified)
		"1.0.1.0/24", "1.0.2.0/23", "1.0.8.0/21", "1.0.32.0/19",
		"14.0.0.0/8", "27.0.0.0/8", "36.0.0.0/8", "39.0.0.0/8",
		"42.0.0.0/8", "49.0.0.0/8", "58.0.0.0/8", "59.0.0.0/8",
		"60.0.0.0/8", "61.0.0.0/8", "101.0.0.0/8", "103.0.0.0/8",
		"106.0.0.0/8", "110.0.0.0/8", "111.0.0.0/8", "112.0.0.0/8",
		"113.0.0.0/8", "114.0.0.0/8", "115.0.0.0/8", "116.0.0.0/8",
		"117.0.0.0/8", "118.0.0.0/8", "119.0.0.0/8", "120.0.0.0/8",
		"121.0.0.0/8", "122.0.0.0/8", "123.0.0.0/8", "124.0.0.0/8",
		"125.0.0.0/8",

		// Russian IP ranges (simplified)
		"5.0.0.0/8", "31.0.0.0/8", "37.0.0.0/8", "46.0.0.0/8",
		"62.0.0.0/8", "77.0.0.0/8", "78.0.0.0/8", "79.0.0.0/8",
		"80.0.0.0/8", "81.0.0.0/8", "82.0.0.0/8", "83.0.0.0/8",
		"84.0.0.0/8", "85.0.0.0/8", "86.0.0.0/8", "87.0.0.0/8",
		"88.0.0.0/8", "89.0.0.0/8", "90.0.0.0/8", "91.0.0.0/8",
		"92.0.0.0/8", "93.0.0.0/8", "94.0.0.0/8", "95.0.0.0/8",
		"128.0.0.0/8", "129.0.0.0/8", "130.0.0.0/8", "131.0.0.0/8",
		"176.0.0.0/8", "178.0.0.0/8", "188.0.0.0/8",

		// Indian IP ranges (simplified)
		"1.6.0.0/15", "1.7.0.0/16", "1.22.0.0/15",
		"27.0.0.0/8", "59.144.0.0/13", "117.192.0.0/10",
		"182.72.0.0/13", "203.0.0.0/8",

		// Brazilian IP ranges (simplified)
		"186.0.0.0/8", "187.0.0.0/8", "189.0.0.0/8",
		"200.0.0.0/8", "201.0.0.0/8",
	}

	for _, rangeStr := range blockedRanges {
		_, block, err := net.ParseCIDR(rangeStr)
		if err != nil {
			continue
		}
		if block.Contains(ip) {
			return true
		}
	}

	// Block common hosting/cloud provider IPs used by bots
	if g.isHostingProvider(ip) {
		return true
	}

	return false
}

// isHostingProvider checks if IP is from known hosting providers often used by bots
func (g *SimpleGeoBlockMiddleware) isHostingProvider(ip net.IP) bool {
	// Common hosting provider ASN prefixes (simplified)
	hostingPrefixes := []string{
		"34.", "35.", "52.", "54.", // AWS
		"104.", "107.", "108.", "172.", // More AWS
		"13.", "18.", "19.", "20.", // Google Cloud
		"8.", "15.", "23.", "66.", // Google
		"4.", "8.", "16.", "23.", // Level 3/CenturyLink
		"64.", "65.", "66.", "67.", "68.", "69.", "70.", "71.", // Various US providers
	}

	for _, prefix := range hostingPrefixes {
		if strings.HasPrefix(ip.String(), prefix) {
			// Additional check - if it's a known datacenter IP range
			if g.isDatacenterIP(ip) {
				return true
			}
		}
	}

	return false
}

// isDatacenterIP checks if IP is from known datacenter ranges
func (g *SimpleGeoBlockMiddleware) isDatacenterIP(ip net.IP) bool {
	// This is a simplified check - in practice you'd want more sophisticated detection
	// For now, just block obvious datacenter ranges
	datacenterRanges := []string{
		"104.16.0.0/12", "172.64.0.0/13", "108.162.192.0/18", // Cloudflare
		"173.245.48.0/20", "188.114.96.0/20", "190.93.240.0/20",
		"197.234.240.0/22", "198.41.128.0/17",
	}

	for _, rangeStr := range datacenterRanges {
		_, block, err := net.ParseCIDR(rangeStr)
		if err != nil {
			continue
		}
		if block.Contains(ip) {
			return true
		}
	}

	return false
}
