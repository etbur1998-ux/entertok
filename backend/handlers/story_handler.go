package handlers

import (
	"net/http"
	"strconv"
	"time"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type StoryHandler struct {
	DB *gorm.DB
}

func NewStoryHandler(db *gorm.DB) *StoryHandler {
	return &StoryHandler{DB: db}
}

// CreateStory creates a new story (expires in 24h)
func (h *StoryHandler) CreateStory(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		MediaURL  string `json:"media_url" binding:"required"`
		MediaType string `json:"media_type"`
		Caption   string `json:"caption"`
		Duration  int    `json:"duration"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	duration := input.Duration
	if duration <= 0 {
		duration = 5
	}

	story := models.Story{
		UserID:    userID,
		MediaURL:  input.MediaURL,
		MediaType: input.MediaType,
		Caption:   input.Caption,
		Duration:  duration,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	}

	if err := h.DB.Create(&story).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create story"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Story created",
		"story":   story,
	})
}

// GetStories returns active stories from followed users
func (h *StoryHandler) GetStories(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	now := time.Now()

	// Get stories from followed users + own stories
	var stories []models.Story
	subQuery := h.DB.Model(&models.Follow{}).
		Where("follower_id = ?", userID).
		Select("following_id")

	h.DB.Where("(user_id IN (?) OR user_id = ?) AND expires_at > ?", subQuery, userID, now).
		Preload("User").
		Order("created_at DESC").
		Find(&stories)

	// Group by user
	userStories := make(map[uint][]gin.H)
	userOrder := []uint{}
	userMap := make(map[uint]gin.H)

	for _, s := range stories {
		if _, exists := userStories[s.UserID]; !exists {
			userOrder = append(userOrder, s.UserID)
			userMap[s.UserID] = gin.H{
				"id":            s.User.ID,
				"username":      s.User.Username,
				"full_name":     s.User.FullName,
				"profile_image": s.User.ProfileImage,
				"is_verified":   s.User.IsVerified,
			}
		}
		userStories[s.UserID] = append(userStories[s.UserID], gin.H{
			"id":         s.ID,
			"media_url":  s.MediaURL,
			"media_type": s.MediaType,
			"caption":    s.Caption,
			"duration":   s.Duration,
			"view_count": s.ViewCount,
			"expires_at": s.ExpiresAt,
			"created_at": s.CreatedAt,
		})
	}

	var result []gin.H
	for _, uid := range userOrder {
		result = append(result, gin.H{
			"user":    userMap[uid],
			"stories": userStories[uid],
		})
	}

	c.JSON(http.StatusOK, gin.H{"story_groups": result})
}

// ViewStory records a story view
func (h *StoryHandler) ViewStory(c *gin.Context) {
	storyID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid story ID"})
		return
	}

	h.DB.Model(&models.Story{}).Where("id = ?", storyID).
		UpdateColumn("view_count", gorm.Expr("view_count + ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Story viewed"})
}

// DeleteStory deletes a story
func (h *StoryHandler) DeleteStory(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	storyID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid story ID"})
		return
	}

	var story models.Story
	if err := h.DB.First(&story, storyID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Story not found"})
		return
	}
	if story.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
		return
	}

	h.DB.Delete(&story)
	c.JSON(http.StatusOK, gin.H{"message": "Story deleted"})
}

// GetUserStories returns stories for a specific user
func (h *StoryHandler) GetUserStories(c *gin.Context) {
	targetUserID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	now := time.Now()
	var stories []models.Story
	h.DB.Where("user_id = ? AND expires_at > ?", targetUserID, now).
		Order("created_at ASC").
		Find(&stories)

	var results []gin.H
	for _, s := range stories {
		results = append(results, gin.H{
			"id":         s.ID,
			"media_url":  s.MediaURL,
			"media_type": s.MediaType,
			"caption":    s.Caption,
			"duration":   s.Duration,
			"view_count": s.ViewCount,
			"expires_at": s.ExpiresAt,
			"created_at": s.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"stories": results})
}
