package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"entertok-backend/models"
	"entertok-backend/websocket"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AdminHandler struct {
	DB *gorm.DB
}

func NewAdminHandler(db *gorm.DB) *AdminHandler {
	return &AdminHandler{DB: db}
}

// GetAllUsers — admin: all users with full details + search + pagination
func (h *AdminHandler) GetAllUsers(c *gin.Context) {
	q := c.Query("q")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	query := h.DB.Model(&models.User{})
	if q != "" {
		like := "%" + strings.ToLower(q) + "%"
		query = query.Where(
			"lower(username) LIKE ? OR lower(full_name) LIKE ? OR lower(email) LIKE ?",
			like, like, like,
		)
	}

	var total int64
	query.Count(&total)

	var users []models.User
	query.Order("id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&users)

	results := make([]gin.H, 0, len(users))
	for _, u := range users {
		results = append(results, gin.H{
			"id":              u.ID,
			"username":        u.Username,
			"full_name":       u.FullName,
			"email":           u.Email,
			"bio":             u.Bio,
			"profile_image":   u.ProfileImage,
			"cover_image":     u.CoverImage,
			"location":        u.Location,
			"website":         u.Website,
			"gender":          u.Gender,
			"role":            u.Role,
			"is_verified":     u.IsVerified,
			"is_private":      u.IsPrivate,
			"is_online":       u.IsOnline,
			"post_count":      u.PostCount,
			"follower_count":  u.FollowerCount,
			"following_count": u.FollowingCount,
			"created_at":      u.CreatedAt,
			"updated_at":      u.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"users": results, "total": total, "page": page, "page_size": pageSize})
}

// GetAllPosts — admin: all posts with user + pagination + filter
func (h *AdminHandler) GetAllPosts(c *gin.Context) {
	q := c.Query("q")
	mediaType := c.Query("type")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "30"))

	query := h.DB.Model(&models.Post{}).Preload("User")
	if q != "" {
		query = query.Where("content LIKE ?", "%"+q+"%")
	}
	if mediaType != "" && mediaType != "all" {
		query = query.Where("media_type = ?", mediaType)
	}

	var total int64
	query.Count(&total)

	var posts []models.Post
	query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&posts)

	results := make([]gin.H, 0, len(posts))
	for _, p := range posts {
		results = append(results, gin.H{
			"id":            p.ID,
			"content":       p.Content,
			"media_url":     p.MediaURL,
			"media_type":    p.MediaType,
			"hashtags":      p.HashTags,
			"like_count":    p.LikeCount,
			"comment_count": p.CommentCount,
			"view_count":    p.ViewCount,
			"share_count":   p.ShareCount,
			"is_public":     p.IsPublic,
			"user_id":       p.UserID,
			"user": gin.H{
				"id":            p.User.ID,
				"username":      p.User.Username,
				"full_name":     p.User.FullName,
				"profile_image": p.User.ProfileImage,
			},
			"created_at": p.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"posts": results, "total": total, "page": page, "page_size": pageSize})
}

// DeleteUserPost — admin: delete any post
func (h *AdminHandler) DeleteUserPost(c *gin.Context) {
	postID, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	h.DB.Delete(&models.Post{}, postID)
	c.JSON(http.StatusOK, gin.H{"message": "Post deleted"})
}

// BanUser — set role to "banned"
func (h *AdminHandler) BanUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	h.DB.Model(&models.User{}).Where("id = ?", id).Update("role", "banned")
	c.JSON(http.StatusOK, gin.H{"message": "User banned"})
}

// UnbanUser — restore role to "user"
func (h *AdminHandler) UnbanUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	h.DB.Model(&models.User{}).Where("id = ?", id).Update("role", "user")
	c.JSON(http.StatusOK, gin.H{"message": "User unbanned"})
}

// VerifyUser — mark as verified
func (h *AdminHandler) VerifyUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	h.DB.Model(&models.User{}).Where("id = ?", id).Update("is_verified", true)
	c.JSON(http.StatusOK, gin.H{"message": "User verified"})
}

// GetAllAds — admin: all ads
func (h *AdminHandler) GetAllAds(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	var total int64
	h.DB.Model(&models.Ad{}).Count(&total)

	var ads []models.Ad
	h.DB.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&ads)

	results := make([]gin.H, 0, len(ads))
	for _, a := range ads {
		results = append(results, gin.H{
			"id":               a.ID,
			"title":            a.Title,
			"description":      a.Description,
			"media_url":        a.MediaURL,
			"media_type":       a.MediaType,
			"format":           a.MediaType,
			"status":           a.Status,
			"budget":           a.Budget,
			"spent":            a.SpentAmount,
			"impression_count": a.ImpressionCount,
			"click_count":      a.ClickCount,
			"target_gender":    a.TargetGender,
			"target_age":       a.TargetAge,
			"target_interests": a.TargetInterests,
			"start_date":       a.StartDate,
			"end_date":         a.EndDate,
			"advertiser_id":    a.AdvertiserID,
			"created_at":       a.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"ads": results, "total": total, "page": page, "page_size": pageSize})
}

// GetAllConversations — admin: all conversations with participant info
func (h *AdminHandler) GetAllConversations(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "40"))
	q := strings.ToLower(c.Query("q"))

	var total int64
	h.DB.Model(&models.Conversation{}).Count(&total)

	var convs []models.Conversation
	h.DB.Order("last_message_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&convs)

	results := make([]gin.H, 0)
	for _, cv := range convs {
		// Load both participants
		var u1, u2 models.User
		h.DB.Select("id,username,full_name,profile_image").First(&u1, cv.Participant1)
		h.DB.Select("id,username,full_name,profile_image").First(&u2, cv.Participant2)

		// Filter by search query
		if q != "" {
			n1 := strings.ToLower(u1.Username + u1.FullName)
			n2 := strings.ToLower(u2.Username + u2.FullName)
			if !strings.Contains(n1, q) && !strings.Contains(n2, q) {
				continue
			}
		}

		// Get last message preview
		lastMsg := ""
		if cv.LastMessageID != nil && *cv.LastMessageID > 0 {
			var lm models.Message
			if h.DB.First(&lm, *cv.LastMessageID).Error == nil {
				if lm.MediaURL != "" {
					lastMsg = "📎 Media"
				} else {
					lastMsg = lm.Content
				}
			}
		}

		// Count total messages
		var msgCount int64
		h.DB.Model(&models.Message{}).Where(
			"(sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)",
			cv.Participant1, cv.Participant2, cv.Participant2, cv.Participant1,
		).Count(&msgCount)

		results = append(results, gin.H{
			"id":       cv.ID,
			"is_group": cv.IsGroup,
			"group_name": cv.GroupName,
			"participant1": gin.H{
				"id": u1.ID, "username": u1.Username,
				"full_name": u1.FullName, "profile_image": u1.ProfileImage,
			},
			"participant2": gin.H{
				"id": u2.ID, "username": u2.Username,
				"full_name": u2.FullName, "profile_image": u2.ProfileImage,
			},
			"last_message":    lastMsg,
			"last_message_at": cv.LastMessageAt,
			"message_count":   msgCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{"conversations": results, "total": total})
}

// GetConversationMessages — admin: read all messages in any conversation
func (h *AdminHandler) GetConversationMessages(c *gin.Context) {
	convID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	var conv models.Conversation
	if err := h.DB.First(&conv, convID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Conversation not found"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "100"))

	var msgs []models.Message
	h.DB.Where(
		"(sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)",
		conv.Participant1, conv.Participant2,
		conv.Participant2, conv.Participant1,
	).Preload("Sender").Preload("Receiver").
		Order("created_at ASC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&msgs)

	results := make([]gin.H, 0, len(msgs))
	for _, m := range msgs {
		results = append(results, gin.H{
			"id":          m.ID,
			"content":     m.Content,
			"media_url":   m.MediaURL,
			"media_type":  m.MediaType,
			"is_read":     m.IsRead,
			"created_at":  m.CreatedAt,
			"sender_id":   m.SenderID,
			"receiver_id": m.ReceiverID,
			"sender": gin.H{
				"id":            m.Sender.ID,
				"username":      m.Sender.Username,
				"full_name":     m.Sender.FullName,
				"profile_image": m.Sender.ProfileImage,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"messages":        results,
		"participant1_id": conv.Participant1,
		"participant2_id": conv.Participant2,
	})
}

// AdminDeleteMessage — admin: delete any message
func (h *AdminHandler) AdminDeleteMessage(c *gin.Context) {
	msgID, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	h.DB.Delete(&models.Message{}, msgID)
	c.JSON(http.StatusOK, gin.H{"message": "Deleted"})
}

// GetStats — overall platform stats
func (h *AdminHandler) GetStats(c *gin.Context) {
	var users, posts, follows, products, liveStreams, ads, messages int64
	h.DB.Model(&models.User{}).Count(&users)
	h.DB.Model(&models.Post{}).Count(&posts)
	h.DB.Model(&models.Follow{}).Count(&follows)
	h.DB.Model(&models.Product{}).Count(&products)
	h.DB.Model(&models.LiveStream{}).Where("is_active = ?", true).Count(&liveStreams)
	h.DB.Model(&models.Ad{}).Count(&ads)
	h.DB.Model(&models.Message{}).Count(&messages)

	var bannedUsers, verifiedUsers int64
	h.DB.Model(&models.User{}).Where("role = ?", "banned").Count(&bannedUsers)
	h.DB.Model(&models.User{}).Where("is_verified = ?", true).Count(&verifiedUsers)

	c.JSON(http.StatusOK, gin.H{
		"users":          users,
		"posts":          posts,
		"follows":        follows,
		"products":       products,
		"live_streams":   liveStreams,
		"ads":            ads,
		"messages":       messages,
		"banned_users":   bannedUsers,
		"verified_users": verifiedUsers,
	})
}

// SendMessageAsAdmin — admin sends a message as a specific user to another user
func (h *AdminHandler) SendMessageAsAdmin(c *gin.Context) {
	var input struct {
		SenderID   uint   `json:"sender_id" binding:"required"`
		ReceiverID uint   `json:"receiver_id" binding:"required"`
		Content    string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Find or create conversation
	var conv models.Conversation
	h.DB.Where(
		"(participant1=? AND participant2=?) OR (participant1=? AND participant2=?)",
		input.SenderID, input.ReceiverID, input.ReceiverID, input.SenderID,
	).First(&conv)

	if conv.ID == 0 {
		conv = models.Conversation{
			Participant1: input.SenderID,
			Participant2: input.ReceiverID,
		}
		h.DB.Create(&conv)
	}

	msg := models.Message{
		SenderID:       input.SenderID,
		ReceiverID:     input.ReceiverID,
		Content:        input.Content,
		ConversationID: conv.ID,
	}
	h.DB.Create(&msg)

	now := time.Now()
	h.DB.Model(&conv).Updates(map[string]interface{}{
		"last_message_id": msg.ID,
		"last_message_at": now,
	})

	h.DB.Preload("Sender").First(&msg, msg.ID)

	// Broadcast via WebSocket
	wsHub := websocket.GetHub()
	if wsHub != nil {
		wsHub.BroadcastChatMessage(input.SenderID, msg.Sender.FullName, msg.Sender.ProfileImage, &msg)
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":         msg.ID,
		"content":    msg.Content,
		"created_at": msg.CreatedAt,
		"sender_id":  msg.SenderID,
		"sender": gin.H{
			"id":            msg.Sender.ID,
			"username":      msg.Sender.Username,
			"full_name":     msg.Sender.FullName,
			"profile_image": msg.Sender.ProfileImage,
		},
	})
}
