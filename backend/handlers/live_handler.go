package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strconv"
	"time"

	"entertok-backend/models"
	"entertok-backend/utils"
	"entertok-backend/websocket"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type LiveHandler struct {
	DB *gorm.DB
}

func NewLiveHandler(db *gorm.DB) *LiveHandler {
	return &LiveHandler{DB: db}
}

// generateStreamKey creates a unique stream key
func generateStreamKey() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// StartLive starts a new live stream
func (h *LiveHandler) StartLive(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		Title        string `json:"title"`
		Description  string `json:"description"`
		ThumbnailURL string `json:"thumbnail_url"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// End any existing active streams for this user
	h.DB.Model(&models.LiveStream{}).
		Where("user_id = ? AND is_active = ?", userID, true).
		Updates(map[string]interface{}{"is_active": false, "ended_at": time.Now()})

	stream := models.LiveStream{
		UserID:       userID,
		Title:        input.Title,
		Description:  input.Description,
		ThumbnailURL: input.ThumbnailURL,
		StreamKey:    generateStreamKey(),
		IsActive:     true,
		StartedAt:    time.Now(),
	}
	if err := h.DB.Create(&stream).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to start live stream"})
		return
	}

	// Load user
	var user models.User
	h.DB.First(&user, userID)

	// Broadcast live start to all connected users
	hub := websocket.GetHub()
	if hub != nil {
		hub.BroadcastLiveStart(&stream, &user)
	}

	c.JSON(http.StatusCreated, gin.H{
		"stream": gin.H{
			"id":            stream.ID,
			"stream_key":    stream.StreamKey,
			"title":         stream.Title,
			"description":   stream.Description,
			"thumbnail_url": stream.ThumbnailURL,
			"is_active":     stream.IsActive,
			"started_at":    stream.StartedAt,
			"viewer_count":  0,
		},
	})
}

// EndLive ends a live stream
func (h *LiveHandler) EndLive(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	streamID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid stream ID"})
		return
	}

	var stream models.LiveStream
	if err := h.DB.First(&stream, streamID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stream not found"})
		return
	}
	if stream.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
		return
	}

	now := time.Now()
	h.DB.Model(&stream).Updates(map[string]interface{}{"is_active": false, "ended_at": now})

	// Broadcast live end
	hub := websocket.GetHub()
	if hub != nil {
		hub.BroadcastLiveEnd(stream.ID)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Live stream ended"})
}

// GetActiveLives returns all active live streams
func (h *LiveHandler) GetActiveLives(c *gin.Context) {
	var streams []models.LiveStream
	h.DB.Where("is_active = ?", true).
		Preload("User").
		Order("viewer_count DESC").
		Find(&streams)

	var results []gin.H
	for _, s := range streams {
		results = append(results, gin.H{
			"id":            s.ID,
			"title":         s.Title,
			"description":   s.Description,
			"thumbnail_url": s.ThumbnailURL,
			"viewer_count":  s.ViewerCount,
			"like_count":    s.LikeCount,
			"started_at":    s.StartedAt,
			"user": gin.H{
				"id":            s.User.ID,
				"username":      s.User.Username,
				"full_name":     s.User.FullName,
				"profile_image": s.User.ProfileImage,
				"is_verified":   s.User.IsVerified,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{"streams": results})
}

// GetLiveStream returns a single live stream
func (h *LiveHandler) GetLiveStream(c *gin.Context) {
	streamID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid stream ID"})
		return
	}

	var stream models.LiveStream
	if err := h.DB.Preload("User").First(&stream, streamID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stream not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":            stream.ID,
		"title":         stream.Title,
		"description":   stream.Description,
		"thumbnail_url": stream.ThumbnailURL,
		"stream_key":    stream.StreamKey,
		"viewer_count":  stream.ViewerCount,
		"like_count":    stream.LikeCount,
		"is_active":     stream.IsActive,
		"started_at":    stream.StartedAt,
		"ended_at":      stream.EndedAt,
		"user": gin.H{
			"id":            stream.User.ID,
			"username":      stream.User.Username,
			"full_name":     stream.User.FullName,
			"profile_image": stream.User.ProfileImage,
			"is_verified":   stream.User.IsVerified,
		},
	})
}

// GetLiveComments returns comments for a live stream
func (h *LiveHandler) GetLiveComments(c *gin.Context) {
	streamID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid stream ID"})
		return
	}

	var comments []models.LiveComment
	h.DB.Where("stream_id = ?", streamID).
		Preload("User").
		Order("created_at DESC").
		Limit(100).
		Find(&comments)

	var results []gin.H
	for _, c := range comments {
		results = append(results, gin.H{
			"id":           c.ID,
			"content":      c.Content,
			"comment_type": c.CommentType,
			"gift_value":   c.GiftValue,
			"created_at":   c.CreatedAt,
			"user": gin.H{
				"id":            c.User.ID,
				"username":      c.User.Username,
				"profile_image": c.User.ProfileImage,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{"comments": results})
}

// SendLiveGift sends a gift during a live stream
func (h *LiveHandler) SendLiveGift(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	streamID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid stream ID"})
		return
	}

	var input struct {
		GiftType  string  `json:"gift_type" binding:"required"`
		GiftValue float64 `json:"gift_value" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	h.DB.First(&user, userID)

	// Save gift as live comment
	comment := models.LiveComment{
		StreamID:    uint(streamID),
		UserID:      userID,
		Content:     "sent a " + input.GiftType,
		CommentType: "gift",
		GiftValue:   input.GiftValue,
	}
	h.DB.Create(&comment)

	// Broadcast gift via WebSocket
	hub := websocket.GetHub()
	if hub != nil {
		var stream models.LiveStream
		h.DB.First(&stream, streamID)
		payload := websocket.LiveCommentPayload{
			StreamID:    uint(streamID),
			UserID:      userID,
			Username:    user.Username,
			Avatar:      user.ProfileImage,
			Content:     "sent a " + input.GiftType,
			CommentType: "gift",
			GiftValue:   input.GiftValue,
		}
		_ = payload
	}

	c.JSON(http.StatusOK, gin.H{"message": "Gift sent successfully"})
}
