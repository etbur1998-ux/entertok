package handlers

import (
	"net/http"
	"strconv"
	"time"

	"entertok-backend/models"
	"entertok-backend/utils"
	"entertok-backend/websocket"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// MessageHandler handles message-related endpoints
type MessageHandler struct {
	DB *gorm.DB
}

// GetConversations returns all conversations for a user
func (h *MessageHandler) GetConversations(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	var conversations []models.Conversation
	h.DB.Where("participant1 = ? OR participant2 = ?", userID, userID).
		Preload("Participant1").
		Preload("Participant2").
		Order("last_message_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&conversations)

	var results []gin.H
	for _, conv := range conversations {
		var otherUserID uint
		if conv.Participant1 == userID {
			otherUserID = conv.Participant2
		} else {
			otherUserID = conv.Participant1
		}

		// Get the user
		var otherUser models.User
		h.DB.First(&otherUser, otherUserID)

		// Get unread count
		var unreadCount int64
		h.DB.Model(&models.Message{}).
			Where("sender_id = ? AND receiver_id = ? AND is_read = ?", otherUser.ID, userID, false).
			Count(&unreadCount)

		// Get last message content
		lastMessageContent := ""
		if conv.LastMessageID != nil && *conv.LastMessageID > 0 {
			var lastMessage models.Message
			if h.DB.First(&lastMessage, *conv.LastMessageID).Error == nil {
				if lastMessage.MediaURL != "" {
					lastMessageContent = "[Media]"
				} else {
					lastMessageContent = lastMessage.Content
				}
			}
		}

		results = append(results, gin.H{
			"id":            conv.ID,
			"user": gin.H{
				"id":             otherUser.ID,
				"username":       otherUser.Username,
				"full_name":      otherUser.FullName,
				"profile_image":  otherUser.ProfileImage,
				"is_verified":    otherUser.IsVerified,
			},
			"last_message":     lastMessageContent,
			"last_message_at": conv.LastMessageAt,
			"unread_count":    unreadCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"conversations": results,
		"page":           page,
		"page_size":      pageSize,
	})
}

// GetMessages returns messages in a conversation
func (h *MessageHandler) GetMessages(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	conversationID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid conversation ID"})
		return
	}

	// Verify user is part of conversation
	var conversation models.Conversation
	if err := h.DB.First(&conversation, conversationID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Conversation not found"})
		return
	}

	if conversation.Participant1 != userID && conversation.Participant2 != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to view this conversation"})
		return
	}

	// Get other user
	var otherUserID uint
	if conversation.Participant1 == userID {
		otherUserID = conversation.Participant2
	} else {
		otherUserID = conversation.Participant1
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	var messages []models.Message
	h.DB.Where("(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)",
		userID, otherUserID, otherUserID, userID).
		Preload("Sender").
		Preload("Receiver").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&messages)

	// Mark messages as read
	h.DB.Model(&models.Message{}).
		Where("sender_id = ? AND receiver_id = ? AND is_read = ?", otherUserID, userID, false).
		Update("is_read", true)

	var results []gin.H
	for _, msg := range messages {
		results = append(results, gin.H{
			"id":         msg.ID,
			"content":    msg.Content,
			"media_url":  msg.MediaURL,
			"media_type": msg.MediaType,
			"is_read":    msg.IsRead,
			"created_at": msg.CreatedAt,
			"sender": gin.H{
				"id":             msg.Sender.ID,
				"username":       msg.Sender.Username,
				"profile_image":  msg.Sender.ProfileImage,
			},
		})
	}

	// Reverse the results to return them in ascending order (oldest first)
	for i, j := 0, len(results)-1; i < j; i, j = i+1, j-1 {
		results[i], results[j] = results[j], results[i]
	}

	c.JSON(http.StatusOK, gin.H{
		"messages":   results,
		"page":       page,
		"page_size":  pageSize,
	})
}

// SendMessage sends a message to another user
func (h *MessageHandler) SendMessage(c *gin.Context) {
	senderID := utils.GetCurrentUserID(c)

	var input struct {
		ReceiverID uint   `json:"receiver_id" binding:"required"`
		Content    string `json:"content" binding:"required"`
		MediaURL   string `json:"media_url"`
		MediaType  string `json:"media_type"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if senderID == input.ReceiverID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot send message to yourself"})
		return
	}

	// Create or find conversation
	var conversation models.Conversation
	h.DB.Where("(participant1 = ? AND participant2 = ?) OR (participant1 = ? AND participant2 = ?)",
		senderID, input.ReceiverID, input.ReceiverID, senderID).
		First(&conversation)

	if conversation.ID == 0 {
		conversation = models.Conversation{
			Participant1: senderID,
			Participant2: input.ReceiverID,
		}
		h.DB.Create(&conversation)
	}

	// Create message
	message := models.Message{
		SenderID:       senderID,
		ReceiverID:     input.ReceiverID,
		Content:        input.Content,
		MediaURL:       input.MediaURL,
		MediaType:      input.MediaType,
		ConversationID: conversation.ID,
	}

	if err := h.DB.Create(&message).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send message"})
		return
	}

	// Update conversation
	now := time.Now()
	h.DB.Model(&conversation).Updates(map[string]interface{}{
		"last_message_id": message.ID,
		"last_message_at": now,
	})

	// Create notification
	notification := models.Notification{
		UserID:  input.ReceiverID,
		Type:    "message",
		ActorID: senderID,
		Message: "sent you a message",
	}
	h.DB.Create(&notification)

	h.DB.Preload("Sender").Preload("Receiver").First(&message, message.ID)

	// Broadcast via WebSocket
	wsHub := websocket.GetHub()
	if wsHub != nil {
		wsHub.BroadcastChatMessage(senderID, message.Sender.FullName, message.Sender.ProfileImage, &message)
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Message sent successfully",
		"data": gin.H{
			"id":         message.ID,
			"content":    message.Content,
			"media_url":  message.MediaURL,
			"media_type": message.MediaType,
			"created_at": message.CreatedAt,
			"sender": gin.H{
				"id":            message.Sender.ID,
				"username":      message.Sender.Username,
				"profile_image": message.Sender.ProfileImage,
			},
		},
	})
}

// GetUnreadCount returns count of unread messages
func (h *MessageHandler) GetUnreadCount(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var count int64
	h.DB.Model(&models.Message{}).
		Where("receiver_id = ? AND is_read = ?", userID, false).
		Count(&count)

	c.JSON(http.StatusOK, gin.H{"unread_count": count})
}

// DeleteMessage deletes a message
func (h *MessageHandler) DeleteMessage(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	messageID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message ID"})
		return
	}

	var message models.Message
	if err := h.DB.First(&message, messageID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Message not found"})
		return
	}

	if message.SenderID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Can only delete your own messages"})
		return
	}

	if err := h.DB.Delete(&message).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete message"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Message deleted successfully"})
}

// UpdateMessage updates a message
func (h *MessageHandler) UpdateMessage(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	messageID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message ID"})
		return
	}

	var input struct {
		Content string `json:"content" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var message models.Message
	if err := h.DB.First(&message, messageID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Message not found"})
		return
	}

	if message.SenderID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Can only edit your own messages"})
		return
	}

	if err := h.DB.Model(&message).Update("content", input.Content).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update message"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Message updated successfully",
		"content": input.Content,
	})
}
