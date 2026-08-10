package handlers

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"entertok-backend/middleware"
	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	DB *gorm.DB
}

// Register handles user registration
func (h *AuthHandler) Register(c *gin.Context) {
	var input struct {
		Username string `json:"username" binding:"required,min=3,max=50"`
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required,min=6"`
		FullName string `json:"full_name"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user already exists
	var existingUser models.User
	if h.DB.Where("email = ?", input.Email).First(&existingUser).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Email already registered"})
		return
	}

	if h.DB.Where("username = ?", input.Username).First(&existingUser).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Username already taken"})
		return
	}

	// Hash password
	hashedPassword, err := utils.HashPassword(input.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to process password"})
		return
	}

	// Create user
	user := models.User{
		Username: input.Username,
		Email:    input.Email,
		Password: hashedPassword,
		FullName: input.FullName,
		Role:     "user",
	}

	if err := h.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
		return
	}

	// Create default wallet for user
	wallet := models.Wallet{
		UserID:   user.ID,
		Balance:  0,
		Currency: "USD",
	}
	h.DB.Create(&wallet)

	// Generate tokens (access + refresh for persistent login)
	token, err := middleware.GenerateToken(user.ID, user.Username, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "User registered successfully",
		"user": gin.H{
			"id":            user.ID,
			"username":      user.Username,
			"email":         user.Email,
			"full_name":     user.FullName,
			"profile_image": user.ProfileImage,
			"role":          user.Role,
		},
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    604800, // 7 days in seconds
	})
}

// Login handles user login
func (h *AuthHandler) Login(c *gin.Context) {
	var input struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Find user by email
	var user models.User
	if err := h.DB.Where("email = ?", input.Email).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Check password
	if !utils.CheckPasswordHash(input.Password, user.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Generate tokens (access + refresh for persistent login)
	token, err := middleware.GenerateToken(user.ID, user.Username, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Login successful",
		"user": gin.H{
			"id":              user.ID,
			"username":        user.Username,
			"email":           user.Email,
			"full_name":       user.FullName,
			"profile_image":   user.ProfileImage,
			"bio":             user.Bio,
			"role":            user.Role,
			"post_count":      user.PostCount,
			"follower_count":  user.FollowerCount,
			"following_count": user.FollowingCount,
		},
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    604800, // 7 days in seconds
	})
}

// GoogleSignIn handles Google OAuth sign-in
func (h *AuthHandler) GoogleSignIn(c *gin.Context) {
	var input struct {
		GoogleID    string `json:"google_id" binding:"required"`
		Email       string `json:"email" binding:"required,email"`
		DisplayName string `json:"display_name"`
		PhotoURL    string `json:"photo_url"`
		IDToken     string `json:"id_token"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user already exists
	var user models.User
	result := h.DB.Where("email = ?", input.Email).First(&user)

	if result.Error == gorm.ErrRecordNotFound {
		// Create new user
		username := generateUsernameFromEmail(input.Email)

		// Make username unique if needed
		var count int64
		h.DB.Model(&models.User{}).Where("username LIKE ?", username+"%").Count(&count)
		if count > 0 {
			username = username + fmt.Sprintf("%d", count+1)
		}

		user = models.User{
			Username:     username,
			Email:        input.Email,
			FullName:     input.DisplayName,
			ProfileImage: input.PhotoURL,
			Password:     "", // No password for OAuth users
			Role:         "user",
			IsVerified:   true,
		}

		if err := h.DB.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
			return
		}

		// Create default wallet
		wallet := models.Wallet{
			UserID:   user.ID,
			Balance:  0,
			Currency: "USD",
		}
		h.DB.Create(&wallet)
	} else if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Generate tokens (access + refresh for persistent login)
	token, err := middleware.GenerateToken(user.ID, user.Username, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Google sign-in successful",
		"user": gin.H{
			"id":              user.ID,
			"username":        user.Username,
			"email":           user.Email,
			"full_name":       user.FullName,
			"profile_image":   user.ProfileImage,
			"bio":             user.Bio,
			"role":            user.Role,
			"post_count":      user.PostCount,
			"follower_count":  user.FollowerCount,
			"following_count": user.FollowingCount,
		},
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    604800, // 7 days in seconds
	})
}

// Helper function to generate username from email
func generateUsernameFromEmail(email string) string {
	// Extract part before @
	parts := strings.Split(email, "@")
	if len(parts) > 0 {
		username := strings.ToLower(parts[0])
		// Remove special characters
		re := regexp.MustCompile("[^a-z0-9]")
		return re.ReplaceAllString(username, "")
	}
	return "user"
}

// GetCurrentUser returns the current authenticated user
func (h *AuthHandler) GetCurrentUser(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":              user.ID,
		"username":        user.Username,
		"email":           user.Email,
		"full_name":       user.FullName,
		"bio":             user.Bio,
		"profile_image":   user.ProfileImage,
		"cover_image":     user.CoverImage,
		"phone":           user.Phone,
		"website":         user.Website,
		"location":        user.Location,
		"birth_date":      user.BirthDate,
		"gender":          user.Gender,
		"is_verified":     user.IsVerified,
		"is_private":      user.IsPrivate,
		"role":            user.Role,
		"post_count":      user.PostCount,
		"follower_count":  user.FollowerCount,
		"following_count": user.FollowingCount,
		"created_at":      user.CreatedAt,
	})
}

// ChangePassword handles password change
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		CurrentPassword string `json:"current_password" binding:"required"`
		NewPassword     string `json:"new_password" binding:"required,min=6"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Verify current password
	if !utils.CheckPasswordHash(input.CurrentPassword, user.Password) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Current password is incorrect"})
		return
	}

	// Hash new password
	hashedPassword, err := utils.HashPassword(input.NewPassword)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to process password"})
		return
	}

	// Update password
	if err := h.DB.Model(&user).Update("password", hashedPassword).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update password"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Password changed successfully"})
}

// RefreshToken handles token refresh for persistent login
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var input struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Refresh token required"})
		return
	}

	// Validate refresh token
	userID, err := middleware.ValidateRefreshToken(input.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired refresh token"})
		return
	}

	// Get user from database
	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Generate new access token
	token, err := middleware.GenerateToken(user.ID, user.Username, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	// Optionally generate new refresh token (rotation for security)
	newRefreshToken, err := middleware.GenerateRefreshToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":         token,
		"refresh_token": newRefreshToken,
		"expires_in":    604800, // 7 days
	})
}
