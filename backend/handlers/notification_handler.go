package handlers

import (
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// NotificationHandler handles notification-related endpoints
type NotificationHandler struct {
	DB *gorm.DB
}

// GetNotifications returns notifications for the current user
func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	var notifications []models.Notification
	h.DB.Where("user_id = ?", userID).
		Preload("Actor").
		Preload("Post").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&notifications)

	var results []gin.H
	for _, n := range notifications {
		result := gin.H{
			"id":         n.ID,
			"type":       n.Type,
			"message":    n.Message,
			"is_read":    n.IsRead,
			"created_at": n.CreatedAt,
			"actor": gin.H{
				"id":             n.Actor.ID,
				"username":       n.Actor.Username,
				"full_name":      n.Actor.FullName,
				"profile_image":  n.Actor.ProfileImage,
			},
		}
		if n.PostID != nil {
			result["post"] = gin.H{
				"id":         n.Post.ID,
				"media_url":  n.Post.MediaURL,
				"thumbnail":  n.Post.Thumbnail,
			}
		}
		results = append(results, result)
	}

	// Get unread count
	var unreadCount int64
	h.DB.Model(&models.Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Count(&unreadCount)

	c.JSON(http.StatusOK, gin.H{
		"notifications":  results,
		"unread_count":  unreadCount,
		"page":          page,
		"page_size":     pageSize,
	})
}

// GetUnreadNotificationCount returns count of unread notifications
func (h *NotificationHandler) GetUnreadCount(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var count int64
	h.DB.Model(&models.Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Count(&count)

	c.JSON(http.StatusOK, gin.H{"unread_count": count})
}

// MarkNotificationAsRead marks a notification as read
func (h *NotificationHandler) MarkAsRead(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	notificationID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	if err := h.DB.Model(&models.Notification{}).
		Where("id = ? AND user_id = ?", notificationID, userID).
		Update("is_read", true).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark notification as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification marked as read"})
}

// MarkAllNotificationsAsRead marks all notifications as read
func (h *NotificationHandler) MarkAllAsRead(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	if err := h.DB.Model(&models.Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Update("is_read", true).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark notifications as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All notifications marked as read"})
}

// DeleteNotification deletes a notification
func (h *NotificationHandler) Delete(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	notificationID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	if err := h.DB.Where("id = ? AND user_id = ?", notificationID, userID).
		Delete(&models.Notification{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete notification"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification deleted"})
}

// SettingsHandler handles notification settings
type SettingsHandler struct {
	DB *gorm.DB
}

// GetNotificationSettings returns notification settings for the current user
func (h *SettingsHandler) GetNotificationSettings(c *gin.Context) {
	// Get user ID from context (if needed for future implementation)
	_ = utils.GetCurrentUserID(c)

	// For now, return default settings - you can extend this with a separate settings table
	c.JSON(http.StatusOK, gin.H{
		"likes":            true,
		"comments":         true,
		"follows":          true,
		"messages":         true,
		"mentions":         true,
		"push_notifications": true,
		"email_notifications": false,
	})
}

// UpdateNotificationSettings updates notification settings
func (h *SettingsHandler) UpdateNotificationSettings(c *gin.Context) {
	// This would typically save to a user settings table
	// For now, just return success
	c.JSON(http.StatusOK, gin.H{"message": "Settings updated"})
}
