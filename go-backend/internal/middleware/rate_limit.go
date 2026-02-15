package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// IPRateLimiter holds rate limiters for each IP address
type IPRateLimiter struct {
	ips      map[string]*rate.Limiter
	mu       sync.Mutex
	r        rate.Limit
	b        int
	lastSeen map[string]time.Time
}

// NewIPRateLimiter creates a new IPRateLimiter
func NewIPRateLimiter(r rate.Limit, b int) *IPRateLimiter {
	l := &IPRateLimiter{
		ips:      make(map[string]*rate.Limiter),
		lastSeen: make(map[string]time.Time),
		r:        r,
		b:        b,
	}

	// Background cleanup of old IPs
	go func() {
		for {
			time.Sleep(time.Minute * 10)
			l.mu.Lock()
			for ip, t := range l.lastSeen {
				if time.Since(t) > time.Minute*30 {
					delete(l.ips, ip)
					delete(l.lastSeen, ip)
				}
			}
			l.mu.Unlock()
		}
	}()

	return l
}

// GetLimiter returns the rate limiter for the provided IP address
func (i *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	i.mu.Lock()
	defer i.mu.Unlock()

	limiter, exists := i.ips[ip]
	if !exists {
		limiter = rate.NewLimiter(i.r, i.b)
		i.ips[ip] = limiter
	}
	i.lastSeen[ip] = time.Now()

	return limiter
}

// RateLimit returns a gin middleware that limits requests by IP
// rps: Requests per second
// burst: Max burst size
func RateLimit(rps float64, burst int) gin.HandlerFunc {
	limiter := NewIPRateLimiter(rate.Limit(rps), burst)

	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !limiter.GetLimiter(ip).Allow() {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "Too many requests. Please try again later.",
			})
			return
		}
		c.Next()
	}
}
