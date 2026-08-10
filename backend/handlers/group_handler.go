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

// GroupHandler handles group-related endpoints
type GroupHandler struct {
	DB *gorm.DB
}

// NewGroupHandler creates a new group handler
func NewGroupHandler(db *gorm.DB) *GroupHandler {
	return &GroupHandler{DB: db}
}

// GetUserGroups returns all groups the current user is a member of
func (h *GroupHandler) GetUserGroups(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	// Find all conversations where user is a member
	var members []models.GroupMember
	h.DB.Where("user_id = ?", userID).
		Preload("Conversation").
		Find(&members)

	var results []gin.H
	for _, m := range members {
		conv := m.Conversation
		if !conv.IsGroup {
			continue
		}

		// Member count
		var memberCount int64
		h.DB.Model(&models.GroupMember{}).
			Where("conversation_id = ?", conv.ID).
			Count(&memberCount)

		// Last message preview
		lastMsg := ""
		if conv.LastMessageID != nil && *conv.LastMessageID > 0 {
			var lm models.Message
			if h.DB.First(&lm, *conv.LastMessageID).Error == nil {
				if lm.MediaURL != "" {
					lastMsg = "📎 Media"
				} else {
					lastMsg = lm.Content
				}
			}
		}

		results = append(results, gin.H{
			"id":              conv.ID,
			"group_name":      conv.GroupName,
			"group_avatar":    conv.GroupAvatar,
			"group_desc":      conv.GroupDesc,
			"member_count":    memberCount,
			"last_message":    lastMsg,
			"last_message_at": conv.LastMessageAt,
			"created_at":      conv.CreatedAt,
			"my_role":         m.Role,
		})
	}

	if results == nil {
		results = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"groups": results, "total": len(results)})
}
func (h *GroupHandler) CreateGroup(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		GroupName string   `json:"group_name" binding:"required"`
		Members   []uint   `json:"members" binding:"required,min=2"`
		GroupAvatar string `json:"group_avatar"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create the group conversation
	conversation := models.Conversation{
		IsGroup:     true,
		GroupName:   input.GroupName,
		GroupAvatar: input.GroupAvatar,
		Participant1: userID,
		Participant2: 0, // Not used for groups
	}

	if err := h.DB.Create(&conversation).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create group"})
		return
	}

	// Add creator as admin
	creatorMember := models.GroupMember{
		ConversationID: conversation.ID,
		UserID:         userID,
		Role:           "admin",
		JoinedAt:       time.Now(),
	}
	h.DB.Create(&creatorMember)

	// Add other members
	for _, memberID := range input.Members {
		if memberID == userID {
			continue // Skip creator
		}
		member := models.GroupMember{
			ConversationID: conversation.ID,
			UserID:         memberID,
			Role:           "member",
			JoinedAt:       time.Now(),
		}
		h.DB.Create(&member)
	}

	// Load members
	var members []models.GroupMember
	h.DB.Preload("User").Where("conversation_id = ?", conversation.ID).Find(&members)

	c.JSON(http.StatusOK, gin.H{
		"conversation": conversation,
		"members":      members,
	})
}

// GetGroup gets a group by ID
func (h *GroupHandler) GetGroup(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	var conversation models.Conversation
	if err := h.DB.Preload("Members.User").First(&conversation, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}

	// Check if user is a member
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, userID).First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "You are not a member of this group"})
		return
	}

	c.JSON(http.StatusOK, conversation)
}

// UpdateGroup updates group info
func (h *GroupHandler) UpdateGroup(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	var input struct {
		GroupName   string `json:"group_name"`
		GroupAvatar string `json:"group_avatar"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var conversation models.Conversation
	if err := h.DB.First(&conversation, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}

	// Check if user is admin
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ? AND role = ?", groupID, userID, "admin").First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can update the group"})
		return
	}

	if input.GroupName != "" {
		conversation.GroupName = input.GroupName
	}
	if input.GroupAvatar != "" {
		conversation.GroupAvatar = input.GroupAvatar
	}

	h.DB.Save(&conversation)

	c.JSON(http.StatusOK, conversation)
}

// AddMembers adds members to a group
func (h *GroupHandler) AddMembers(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	var input struct {
		Members []uint `json:"members" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user is admin or moderator
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ? AND role IN ?", groupID, userID, []string{"admin", "moderator"}).First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins and moderators can add members"})
		return
	}

	var addedMembers []models.GroupMember
	for _, memberID := range input.Members {
		// Check if already a member
		var existing models.GroupMember
		if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, memberID).First(&existing).Error; err == nil {
			continue // Already a member
		}

		newMember := models.GroupMember{
			ConversationID: uint(groupID),
			UserID:         memberID,
			Role:           "member",
			JoinedAt:       time.Now(),
		}
		h.DB.Create(&newMember)
		addedMembers = append(addedMembers, newMember)
	}

	// Load full member info
	h.DB.Preload("User").Where("conversation_id = ?", groupID).Find(&addedMembers)

	c.JSON(http.StatusOK, gin.H{
		"message": "Members added successfully",
		"members": addedMembers,
	})
}

// RemoveMember removes a member from a group
func (h *GroupHandler) RemoveMember(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	memberID, err := strconv.ParseUint(c.Param("member_id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid member ID"})
		return
	}

	// Check if user is admin or removing themselves
	if userID != uint(memberID) {
		var member models.GroupMember
		if err := h.DB.Where("conversation_id = ? AND user_id = ? AND role = ?", groupID, userID, "admin").First(&member).Error; err != nil {
			c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can remove other members"})
			return
		}
	}

	// Cannot remove admin
	var targetMember models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, memberID).First(&targetMember).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Member not found"})
		return
	}

	if targetMember.Role == "admin" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot remove admin"})
		return
	}

	h.DB.Delete(&targetMember)

	c.JSON(http.StatusOK, gin.H{"message": "Member removed successfully"})
}

// LeaveGroup allows a user to leave a group
func (h *GroupHandler) LeaveGroup(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, userID).First(&member).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "You are not a member of this group"})
		return
	}

	// Cannot leave if only admin
	if member.Role == "admin" {
		var count int64
		h.DB.Model(&models.GroupMember{}).Where("conversation_id = ?", groupID).Count(&count)
		if count <= 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot leave as the only admin. Transfer admin role first."})
			return
		}
	}

	h.DB.Delete(&member)

	c.JSON(http.StatusOK, gin.H{"message": "Left group successfully"})
}

// GetGroupMembers gets all members of a group
func (h *GroupHandler) GetGroupMembers(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	// Check if user is a member
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, userID).First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "You are not a member of this group"})
		return
	}

	var members []models.GroupMember
	h.DB.Preload("User").Where("conversation_id = ?", groupID).Find(&members)

	c.JSON(http.StatusOK, members)
}

// SendGroupMessage sends a message to a group
func (h *GroupHandler) SendGroupMessage(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	var input struct {
		Content  string `json:"content" binding:"required"`
		MediaURL string `json:"media_url"`
		MediaType string `json:"media_type"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user is a member
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, userID).First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "You are not a member of this group"})
		return
	}

	// Get user info
	var user models.User
	h.DB.First(&user, userID)

	// Create message
	message := models.Message{
		SenderID:       userID,
		ReceiverID:     0, // Group message
		Content:        input.Content,
		MediaURL:       input.MediaURL,
		MediaType:      input.MediaType,
		IsGroup:        true,
		GroupID:        uint(groupID),
		ConversationID: uint(groupID),
	}

	if err := h.DB.Create(&message).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send message"})
		return
	}

	// Update conversation
	now := time.Now()
	h.DB.Model(&models.Conversation{}).Where("id = ?", groupID).Updates(map[string]interface{}{
		"last_message_id": message.ID,
		"last_message_at": now,
	})

	// Load sender info
	h.DB.Preload("Sender").First(&message, message.ID)

	// Broadcast via WebSocket
	wsHub := websocket.GetHub()
	if wsHub != nil {
		wsHub.BroadcastGroupMessage(userID, message.Sender.FullName, message.Sender.ProfileImage, &message)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": message,
		"sender": gin.H{
			"id":          user.ID,
			"username":    user.Username,
			"full_name":   user.FullName,
			"profile_image": user.ProfileImage,
		},
	})
}

// GetGroupMessages gets messages in a group
func (h *GroupHandler) GetGroupMessages(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group ID"})
		return
	}

	// Check if user is a member
	var member models.GroupMember
	if err := h.DB.Where("conversation_id = ? AND user_id = ?", groupID, userID).First(&member).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "You are not a member of this group"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	var messages []models.Message
	h.DB.Preload("Sender").
		Where("group_id = ?", groupID).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&messages)

	// Mark messages as read
	h.DB.Model(&models.Message{}).
		Where("group_id = ? AND sender_id != ?", groupID, userID).
		Update("is_read", true)

	// Update last read time
	h.DB.Model(&member).Update("last_read_at", time.Now())

	// Reverse messages slice so they are returned in ascending order (oldest first)
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	c.JSON(http.StatusOK, gin.H{
		"messages": messages,
		"page":     page,
		"page_size": pageSize,
	})
}
