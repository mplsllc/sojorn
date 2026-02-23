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

// sendBufSize is the number of outbound messages buffered per client.
// If the buffer fills (slow consumer) messages are dropped rather than
// blocking the hub — the correct trade-off for real-time social features
// where staleness is preferable to head-of-line blocking.
const sendBufSize = 64

// Client represents a single WebSocket connection.
//
// Architecture: each Client owns a dedicated WritePump goroutine that is the
// SOLE writer to Conn. This satisfies gorilla/websocket's one-concurrent-writer
// requirement without any external mutex on the socket.
//
// The old hub.go used time.After(1*time.Second) inside SendToUser, which:
//   - Leaked a goroutine-backed timer per send call until GC ran
//   - Blocked ALL sends to a user if even one device was slow
//   - Could cascade into hub-wide latency under load
//
// The new model: SendToUser is a non-blocking channel push. WritePump drains
// the channel serially. If the buffer fills, the client is torn down.
type Client struct {
	UserID string
	Conn   *websocket.Conn
	Send   chan interface{}
}

// NewClient allocates a Client with a buffered send channel.
// Call WritePump in a separate goroutine immediately after registering.
func NewClient(userID string, conn *websocket.Conn) *Client {
	return &Client{
		UserID: userID,
		Conn:   conn,
		Send:   make(chan interface{}, sendBufSize),
	}
}

// WritePump must run in its own goroutine. It is the sole writer to Conn.
// Returns when the Send channel is closed or a write error occurs.
func (c *Client) WritePump(hub *Hub) {
	defer func() {
		hub.Unregister(c)
	}()

	// Periodic ping keeps the OS TCP stack alive and surfaces dead peers.
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case msg, ok := <-c.Send:
			if !ok {
				// Hub closed the channel — send a WebSocket CloseMessage.
				_ = c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.Conn.WriteJSON(msg); err != nil {
				log.Warn().Str("user_id", c.UserID).Err(err).Msg("WebSocket write error")
				return
			}

		case <-ticker.C:
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

type Hub struct {
	// Map userID -> set of clients (multi-device support).
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
			// Closing Send signals WritePump to send a close frame and exit.
			// Guard with recover in case it was already closed.
			func() {
				defer func() { recover() }() //nolint:errcheck
				close(client.Send)
			}()
			_ = client.Conn.Close()
			delete(userClients, client)
			if len(userClients) == 0 {
				delete(h.clients, client.UserID)
			}
			log.Info().Str("user_id", client.UserID).Msg("Unregistered WebSocket client")
		}
	}
}

// SendToUser delivers a message to all devices connected as userID.
//
// Fully non-blocking: if a client's buffer is full the message is dropped
// for that client and the client is scheduled for teardown. No goroutine
// or timer is created for the happy path.
func (h *Hub) SendToUser(userID string, message interface{}) error {
	h.mu.RLock()
	userClients, ok := h.clients[userID]
	h.mu.RUnlock()

	if !ok {
		return nil // User not connected.
	}

	for client := range userClients {
		select {
		case client.Send <- message:
			// Enqueued to WritePump buffer.
		default:
			// Buffer full — congested client. Tear down asynchronously so
			// the hot path (iterating other clients) is not blocked.
			log.Debug().Str("user_id", userID).Msg("Send buffer full — tearing down client")
			go h.Unregister(client)
		}
	}

	return nil
}

// Broadcast delivers a message to every connected client across all users.
// Useful for server-wide notices (e.g. maintenance window, feature flags).
func (h *Hub) Broadcast(message interface{}) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for _, userClients := range h.clients {
		for client := range userClients {
			select {
			case client.Send <- message:
			default:
				go h.Unregister(client)
			}
		}
	}
}

// ConnectedCount returns the total number of open WebSocket connections.
func (h *Hub) ConnectedCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	n := 0
	for _, clients := range h.clients {
		n += len(clients)
	}
	return n
}
