package utils

import (
	"os"
	"strconv"

	"golang.org/x/crypto/bcrypt"

	"github.com/gin-gonic/gin"
)

// HashPassword generates a bcrypt hash of the password
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

// CheckPasswordHash compares a password with a hash
func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// GetEnv returns environment variable or default value
func GetEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// GetCurrentUserID extracts user ID from context
func GetCurrentUserID(c *gin.Context) uint {
	userID, exists := c.Get("user_id")
	if !exists {
		return 0
	}
	return userID.(uint)
}

// PaginateParams holds pagination parameters
type PaginateParams struct {
	Page     int
	PageSize int
}

// DefaultPagination returns default pagination parameters
func DefaultPagination() PaginateParams {
	return PaginateParams{
		Page:     1,
		PageSize: 20,
	}
}

// GetPagination returns pagination parameters from query
func GetPagination(c *gin.Context) PaginateParams {
	page := 1
	pageSize := 20

	if p := c.Query("page"); p != "" {
		if n, err := strconv.Atoi(p); err == nil && n > 0 {
			page = n
		}
	}

	if ps := c.Query("page_size"); ps != "" {
		if n, err := strconv.Atoi(ps); err == nil && n > 0 && n <= 100 {
			pageSize = n
		}
	}

	return PaginateParams{
		Page:     page,
		PageSize: pageSize,
	}
}
