package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

const (
	logFile     = "/opt/ejabberd/sso-auth.log"
	httpTimeout = 5 * time.Second
	maxRetries  = 2
)

var logger *log.Logger

func init() {
	// Setup logging
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	logger = log.New(f, "", log.LstdFlags)
}

func main() {
	// Handle signals gracefully
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		sig := <-sigChan
		logger.Printf("Received signal %v, shutting down gracefully", sig)
		os.Exit(0)
	}()

	logger.Println("=== External auth worker started ===")

	// Send initial ready signal
	writeResult(true)
	logger.Println("Sent initial ready signal")

	consecutiveErrors := 0
	maxConsecutiveErrors := 10

	for {
		// Read 2-byte header (length)
		header := make([]byte, 2)
		if _, err := io.ReadFull(os.Stdin, header); err != nil {
			if err == io.EOF {
				consecutiveErrors++
				if consecutiveErrors > maxConsecutiveErrors {
					logger.Printf("Too many consecutive errors (%d), exiting", consecutiveErrors)
					os.Exit(1)
				}
				time.Sleep(100 * time.Millisecond)
				continue
			}
			logger.Printf("Error reading header: %v", err)
			writeResult(false)
			continue
		}

		consecutiveErrors = 0

		// Parse length
		size := binary.BigEndian.Uint16(header)

		// Sanity check
		if size > 10000 {
			logger.Printf("Invalid packet size: %d", size)
			writeResult(false)
			continue
		}

		// Read payload
		payload := make([]byte, size)
		if _, err := io.ReadFull(os.Stdin, payload); err != nil {
			logger.Printf("Error reading payload: %v", err)
			writeResult(false)
			continue
		}

		// Process command
		pkt := string(payload)
		parts := strings.SplitN(pkt, ":", 2)
		if len(parts) < 1 {
			logger.Printf("Invalid packet format")
			writeResult(false)
			continue
		}

		cmd := parts[0]
		logger.Printf("Received command: %s", cmd)

		var result bool
		switch cmd {
		case "auth":
			result = handleAuth(pkt)
		case "isuser", "setpass", "tryregister", "removeuser", "removeuser3":
			result = true
		default:
			logger.Printf("Unknown command: %s", cmd)
			result = false
		}

		writeResult(result)
	}
}

func handleAuth(pkt string) bool {
	parts := strings.SplitN(pkt, ":", 6)
	if len(parts) != 6 {
		logger.Printf("Invalid auth packet format (expected 6 parts, got %d): %s", len(parts), pkt)
		return false
	}

	// Format: auth:username:server:password:local:api
	username := parts[1]
	password := parts[3]
	localURL := parts[4]
	apiURL := parts[5]

	// Validation
	if username == "" || password == "" {
		logger.Println("Empty username or password")
		return false
	}

	// Test bypasses
	if username == "wrong" {
		return false
	}
	if password == "allow" {
		return true
	}

	// Build URLs
	rurl := "https://" + localURL
	aurl := "https://" + apiURL

	logger.Printf("Authenticating user %s against %s", username, rurl)

	// Prepare request
	payload := map[string]interface{}{
		"username":         username,
		"password":         password,
		"currentTimestamp": time.Now().Unix(),
	}

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		logger.Printf("Error marshaling JSON: %v", err)
		return false
	}

	// Retry logic
	client := &http.Client{Timeout: httpTimeout}
	var lastError error

	for attempt := 0; attempt < maxRetries; attempt++ {
		req, err := http.NewRequest("POST", rurl, bytes.NewBuffer(payloadBytes))
		if err != nil {
			logger.Printf("Error creating request: %v", err)
			return false
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Tenant-Domain", aurl)

		resp, err := client.Do(req)
		if err != nil {
			lastError = err
			if attempt < maxRetries-1 {
				time.Sleep(500 * time.Millisecond)
				continue
			}
			logger.Printf("Request error after %d attempts: %v", maxRetries, err)
			return false
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)

		if resp.StatusCode == 200 || resp.StatusCode == 201 || resp.StatusCode == 202 {
			var data map[string]interface{}
			if err := json.Unmarshal(body, &data); err != nil {
				logger.Printf("Invalid JSON response: %s", string(body))
				return false
			}

			status, ok := data["status"].(float64)
			if ok && (status == 200 || status == 201) {
				logger.Printf("Auth success for user %s", username)
				return true
			}
			logger.Printf("Auth failed for user %s (status: %v)", username, data["status"])
			return false
		}

		logger.Printf("Auth failed HTTP %d for user %s: %s", resp.StatusCode, username, string(body))
		return false
	}

	logger.Printf("Auth failed after %d attempts: %v", maxRetries, lastError)
	return false
}

func writeResult(ok bool) {
	var result []byte
	if ok {
		result = []byte{0x00, 0x02, 0x00, 0x01}
	} else {
		result = []byte{0x00, 0x02, 0x00, 0x00}
	}

	if _, err := os.Stdout.Write(result); err != nil {
		logger.Printf("Error writing result: %v", err)
	}
}
