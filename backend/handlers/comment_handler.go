package handlers

import (
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// CommentHandler handles comment-related endpoints
type CommentHandler struct {
	DB *gorm.DB
}

// GetComments returns comments for a post
func (h *CommentHandler) GetComments(c *gin.Context) {
	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	var comments []models.Comment
	h.DB.Where("post_id = ? AND parent_id IS NULL", postID).
		Preload("User").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&comments)

	var results []gin.H
	for _, comment := range comments {
		// Get replies
		var replies []models.Comment
		h.DB.Where("parent_id = ?", comment.ID).
			Preload("User").
			Order("created_at ASC").
			Find(&replies)

		var replyResults []gin.H
		for _, reply := range replies {
			replyResults = append(replyResults, gin.H{
				"id":         reply.ID,
				"content":    reply.Content,
				"like_count": reply.LikeCount,
				"created_at": reply.CreatedAt,
				"user": gin.H{
					"id":             reply.User.ID,
					"username":       reply.User.Username,
					"full_name":      reply.User.FullName,
					"profile_image":  reply.User.ProfileImage,
				},
			})
		}

		results = append(results, gin.H{
			"id":         comment.ID,
			"content":    comment.Content,
			"like_count": comment.LikeCount,
			"created_at": comment.CreatedAt,
			"user": gin.H{
				"id":             comment.User.ID,
				"username":       comment.User.Username,
				"full_name":      comment.User.FullName,
				"profile_image":  comment.User.ProfileImage,
			},
			"replies": replyResults,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"comments":  results,
		"page":      page,
		"page_size": pageSize,
	})
}

// CreateComment creates a new comment on a post
func (h *CommentHandler) CreateComment(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	var input struct {
		Content  string `json:"content" binding:"required"`
		ParentID *uint  `json:"parent_id"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify post exists
	var post models.Post
	if err := h.DB.First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	comment := models.Comment{
		PostID:   uint(postID),
		UserID:   userID,
		ParentID: input.ParentID,
		Content:  input.Content,
	}

	if err := h.DB.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create comment"})
		return
	}

	// Update comment count
	h.DB.Model(&post).UpdateColumn("comment_count", gorm.Expr("comment_count + ?", 1))

	// Create notification
	if post.UserID != userID {
		notification := models.Notification{
			UserID:  post.UserID,
			Type:    "comment",
			ActorID: userID,
			PostID:  &post.ID,
			Message: "commented on your post",
		}
		h.DB.Create(&notification)
	}

	h.DB.Preload("User").First(&comment, comment.ID)

	c.JSON(http.StatusCreated, gin.H{
		"message": "Comment created successfully",
		"comment": gin.H{
			"id":         comment.ID,
			"content":    comment.Content,
			"like_count": comment.LikeCount,
			"created_at": comment.CreatedAt,
			"user": gin.H{
				"id":             comment.User.ID,
				"username":       comment.User.Username,
				"full_name":      comment.User.FullName,
				"profile_image":  comment.User.ProfileImage,
			},
		},
	})
}

// DeleteComment deletes a comment
func (h *CommentHandler) DeleteComment(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	commentID, err := strconv.ParseUint(c.Param("commentId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	var comment models.Comment
	if err := h.DB.First(&comment, commentID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Comment not found"})
		return
	}

	// Check ownership
	if comment.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only delete your own comments"})
		return
	}

	// Get post for updating count
	var post models.Post
	h.DB.First(&post, comment.PostID)

	if err := h.DB.Delete(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete comment"})
		return
	}

	// Update comment count
	h.DB.Model(&post).UpdateColumn("comment_count", gorm.Expr("comment_count - ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Comment deleted successfully"})
}

// LikeComment likes a comment
func (h *CommentHandler) LikeComment(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	commentID, err := strconv.ParseUint(c.Param("commentId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	// Check if already liked
	var existingLike models.CommentLike
	if h.DB.Where("user_id = ? AND comment_id = ?", userID, commentID).First(&existingLike).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Already liked"})
		return
	}

	like := models.CommentLike{
		CommentID: uint(commentID),
		UserID:    userID,
	}

	if err := h.DB.Create(&like).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like comment"})
		return
	}

	// Update like count
	h.DB.Model(&models.Comment{}).Where("id = ?", commentID).UpdateColumn("like_count", gorm.Expr("like_count + ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Comment liked successfully"})
}

// UnlikeComment unlikes a comment
func (h *CommentHandler) UnlikeComment(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	commentID, err := strconv.ParseUint(c.Param("commentId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	result := h.DB.Where("user_id = ? AND comment_id = ?", userID, commentID).Delete(&models.CommentLike{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike comment"})
		return
	}

	if result.RowsAffected > 0 {
		h.DB.Model(&models.Comment{}).Where("id = ?", commentID).UpdateColumn("like_count", gorm.Expr("like_count - ?", 1))
	}

	c.JSON(http.StatusOK, gin.H{"message": "Comment unliked successfully"})
}
