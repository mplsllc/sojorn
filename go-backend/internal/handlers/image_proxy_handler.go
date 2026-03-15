// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ImageProxyHandler proxies external image URLs so the Flutter web client
// avoids CORS restrictions (e.g. web.archive.org does not set Access-Control headers).
type ImageProxyHandler struct {
	client *http.Client
}

func NewImageProxyHandler() *ImageProxyHandler {
	return &ImageProxyHandler{
		client: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

// allowedHosts restricts which origins the proxy will fetch from
// to prevent open-relay abuse.
var allowedProxyHosts = map[string]bool{
	"web.archive.org":                          true,
	"i.imgur.com":                              true,
	"media.giphy.com":                          true,
	"crc-signs-s3.s3.us-west-2.amazonaws.com": true,
}

// ProxyImage handles GET /image-proxy?url=<encoded-url>
func (h *ImageProxyHandler) ProxyImage(c *gin.Context) {
	rawURL := c.Query("url")
	if rawURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url parameter required"})
		return
	}

	parsed, err := url.Parse(rawURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid url"})
		return
	}

	if !allowedProxyHosts[parsed.Hostname()] {
		c.JSON(http.StatusForbidden, gin.H{"error": "host not allowed"})
		return
	}

	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, rawURL, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}
	req.Header.Set("User-Agent", "SojornAPI/1.0")

	resp, err := h.client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream request failed"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.Status(resp.StatusCode)
		return
	}

	ct := resp.Header.Get("Content-Type")
	if ct == "" || !strings.HasPrefix(ct, "image/") {
		ct = "application/octet-stream"
	}

	// Cache proxied images for 1 hour
	c.Header("Cache-Control", "public, max-age=3600")
	c.DataFromReader(http.StatusOK, resp.ContentLength, ct, resp.Body, nil)
}
