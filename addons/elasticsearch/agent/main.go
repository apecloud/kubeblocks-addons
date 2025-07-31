package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
)

type KeystoreRequest struct {
	AccessKeyID     string `json:"access_key_id" binding:"required"`
	SecretAccessKey string `json:"secret_access_key" binding:"required"`
}

var (
	esUsername = os.Getenv("ELASTIC_USERNAME")
	esPassword = os.Getenv("ELASTIC_PASSWORD")
	agentPort  = os.Getenv("AGENT_PORT")
)

func init() {
	if agentPort == "" {
		agentPort = "8080"
	}
}

func main() {
	r := gin.Default()

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Set keystore endpoint
	r.POST("/keystore", authMiddleware(), setKeystore)

	log.Printf("Agent starting on port %s", agentPort)
	r.Run(":" + agentPort)
}

func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip authentication if ES doesn't have authentication enabled
		if esUsername == "" || esPassword == "" {
			c.Next()
			return
		}

		username, password, hasAuth := c.Request.BasicAuth()
		if !hasAuth || username != esUsername || password != esPassword {
			c.Header("WWW-Authenticate", "Basic realm=Restricted")
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			return
		}
		c.Next()
	}
}

func setKeystore(c *gin.Context) {
	var req KeystoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := updateKeystore(req.AccessKeyID, req.SecretAccessKey); err != nil {
		log.Printf("Failed to update keystore: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Keystore updated successfully"})
}

func updateKeystore(accessKeyID, secretAccessKey string) error {
	// Set access key
	cmd := exec.Command("elasticsearch-keystore", "add", "s3.client.default.access_key", "-f")
	cmd.Stdin = strings.NewReader(accessKeyID)
	cmd.Env = append(os.Environ(), "PATH=/usr/share/elasticsearch/bin:"+os.Getenv("PATH"))
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to set access key: %v, output: %s", err, output)
	}

	// Set secret key
	cmd = exec.Command("elasticsearch-keystore", "add", "s3.client.default.secret_key", "-f")
	cmd.Stdin = strings.NewReader(secretAccessKey)
	cmd.Env = append(os.Environ(), "PATH=/usr/share/elasticsearch/bin:"+os.Getenv("PATH"))
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to set secret key: %v, output: %s", err, output)
	}
	return nil
}
