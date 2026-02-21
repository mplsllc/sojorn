// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package realtime

import (
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/rs/zerolog/log"
)

type Client struct {
	UserID string
	Conn   *websocket.Conn
	Send   chan interface{}
}

type Hub struct {
	// Map userID -> set of clients (multi-device)
	clients map[string]map[*Client]bool
	mu      sync.RWMutex
}

func NewHub() *Hub {
	return &Hub{
		clients: make(map[string]map[*Client]bool),
	}
}

func (h *Hub) Register(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, ok := h.clients[client.UserID]; !ok {
		h.clients[client.UserID] = make(map[*Client]bool)
	}
	h.clients[client.UserID][client] = true
	log.Info().Str("user_id", client.UserID).Msg("Registered WebSocket client")
}

func (h *Hub) Unregister(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if userClients, ok := h.clients[client.UserID]; ok {
		if _, exists := userClients[client]; exists {
			client.Conn.Close()
			delete(userClients, client)
			if len(userClients) == 0 {
				delete(h.clients, client.UserID)
			}
			log.Info().Str("user_id", client.UserID).Msg("Unregistered WebSocket client")
		}
	}
}

func (h *Hub) SendToUser(userID string, message interface{}) error {
	h.mu.RLock()
	userClients, ok := h.clients[userID]
	h.mu.RUnlock()

	if !ok {
		return nil // User not connected
	}

	for client := range userClients {
		// Use the channel to ensure single-writer concurrency
		select {
		case client.Send <- message:
		case <-time.After(1 * time.Second):
			log.Warn().Str("user_id", userID).Msg("Timed out sending message to client channel")
			go h.Unregister(client)
		}
	}

	return nil
}
