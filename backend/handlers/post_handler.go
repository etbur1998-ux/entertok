package handlers

import (
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"entertok-backend/websocket"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// PostHandler handles post-related endpoints
type PostHandler struct {
	DB *gorm.DB
}

// CreatePost creates a new post/video
func (h *PostHandler) CreatePost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		Content        string `json:"content"`
		MediaURL       string `json:"media_url"`
		MediaType      string `json:"media_type"`
		Thumbnail      string `json:"thumbnail"`
		Duration       int    `json:"duration"`
		Location       string `json:"location"`
		HashTags       string `json:"hash_tags"`
		MentionedUsers string `json:"mentioned_users"`
		IsPublic       *bool  `json:"is_public"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.MediaURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Media URL is required"})
		return
	}

	isPublic := true
	if input.IsPublic != nil {
		isPublic = *input.IsPublic
	}

	post := models.Post{
		UserID:         userID,
		Content:        input.Content,
		MediaURL:       input.MediaURL,
		MediaType:      input.MediaType,
		Thumbnail:      input.Thumbnail,
		Duration:       input.Duration,
		Location:       input.Location,
		HashTags:       input.HashTags,
		MentionedUsers: input.MentionedUsers,
		IsPublic:       isPublic,
	}

	if err := h.DB.Create(&post).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create post"})
		return
	}

	// Update post count
	h.DB.Model(&models.User{}).Where("id = ?", userID).UpdateColumn("post_count", gorm.Expr("post_count + ?", 1))

	// Load user
	h.DB.Preload("User").First(&post, post.ID)

	// Broadcast new post via WebSocket
	websocket.GetHub().BroadcastNewPost(&post)

	c.JSON(http.StatusCreated, gin.H{
		"message": "Post created successfully",
		"post":    post,
	})
}

// GetPost returns a single post by ID
func (h *PostHandler) GetPost(c *gin.Context) {
	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	var post models.Post
	if err := h.DB.Preload("User").First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	// Increment view count
	h.DB.Model(&post).UpdateColumn("view_count", gorm.Expr("view_count + ?", 1))

	currentUserID := utils.GetCurrentUserID(c)
	var isLiked bool
	if currentUserID > 0 {
		var like models.Like
		isLiked = h.DB.Where("user_id = ? AND post_id = ?", currentUserID, postID).First(&like).Error == nil
	}

	c.JSON(http.StatusOK, gin.H{
		"id":            post.ID,
		"content":       post.Content,
		"media_url":     post.MediaURL,
		"media_type":    post.MediaType,
		"thumbnail":     post.Thumbnail,
		"duration":      post.Duration,
		"location":      post.Location,
		"hash_tags":     post.HashTags,
		"view_count":    post.ViewCount + 1,
		"like_count":    post.LikeCount,
		"comment_count": post.CommentCount,
		"share_count":   post.ShareCount,
		"is_public":     post.IsPublic,
		"created_at":    post.CreatedAt,
		"user": gin.H{
			"id":            post.User.ID,
			"username":      post.User.Username,
			"full_name":     post.User.FullName,
			"profile_image": post.User.ProfileImage,
			"is_verified":   post.User.IsVerified,
		},
		"is_liked": isLiked,
	})
}

// GetFeed returns posts for the feed with batched like/follow lookups (no N+1)
func (h *PostHandler) GetFeed(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if pageSize > 30 { pageSize = 30 }

	currentUserID := utils.GetCurrentUserID(c)

	var posts []models.Post

	if currentUserID > 0 {
		// Posts from followed users + own posts, random order
		subQuery := h.DB.Model(&models.Follow{}).
			Where("follower_id = ?", currentUserID).
			Select("following_id")
		h.DB.Where("(user_id IN (?) OR user_id = ?) AND is_public = ?", subQuery, currentUserID, true).
			Preload("User").
			Order("RANDOM()").
			Offset((page - 1) * pageSize).
			Limit(pageSize).
			Find(&posts)
	}

	// Pad with random public posts if we don't have enough
	if len(posts) < pageSize {
		needed := pageSize - len(posts)
		existingIDs := make([]uint, len(posts))
		for i, p := range posts { existingIDs[i] = p.ID }

		var extra []models.Post
		q := h.DB.Where("is_public = ?", true)
		if len(existingIDs) > 0 {
			q = q.Where("id NOT IN ?", existingIDs)
		}
		q.Preload("User").
			Order("RANDOM()").
			Limit(needed).
			Find(&extra)
		posts = append(posts, extra...)
	}

	if len(posts) == 0 {
		c.JSON(http.StatusOK, gin.H{"posts": []gin.H{}, "page": page, "page_size": pageSize})
		return
	}

	// ── Batch fetch liked post IDs ──────────────────────────────────────────
	postIDs := make([]uint, len(posts))
	for i, p := range posts { postIDs[i] = p.ID }

	likedSet := map[uint]bool{}
	if currentUserID > 0 {
		var likedIDs []uint
		h.DB.Model(&models.Like{}).
			Where("user_id = ? AND post_id IN ?", currentUserID, postIDs).
			Pluck("post_id", &likedIDs)
		for _, id := range likedIDs { likedSet[id] = true }
	}

	// ── Batch fetch followed user IDs ───────────────────────────────────────
	followedSet := map[uint]bool{}
	if currentUserID > 0 {
		ownerIDs := make([]uint, len(posts))
		for i, p := range posts { ownerIDs[i] = p.UserID }
		var followedIDs []uint
		h.DB.Model(&models.Follow{}).
			Where("follower_id = ? AND following_id IN ?", currentUserID, ownerIDs).
			Pluck("following_id", &followedIDs)
		for _, id := range followedIDs { followedSet[id] = true }
	}

	// ── Build response ──────────────────────────────────────────────────────
	results := make([]gin.H, 0, len(posts))
	postIDsToView := make([]uint, 0, len(posts))
	for _, p := range posts {
		postIDsToView = append(postIDsToView, p.ID)
		results = append(results, gin.H{
			"id":            p.ID,
			"content":       p.Content,
			"media_url":     p.MediaURL,
			"media_type":    p.MediaType,
			"thumbnail":     p.Thumbnail,
			"duration":      p.Duration,
			"location":      p.Location,
			"hash_tags":     p.HashTags,
			"view_count":    p.ViewCount,
			"like_count":    p.LikeCount,
			"comment_count": p.CommentCount,
			"share_count":   p.ShareCount,
			"created_at":    p.CreatedAt,
			"is_liked":      likedSet[p.ID],
			"user": gin.H{
				"id":            p.User.ID,
				"username":      p.User.Username,
				"full_name":     p.User.FullName,
				"profile_image": p.User.ProfileImage,
				"is_verified":   p.User.IsVerified,
				"is_following":  followedSet[p.UserID],
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"posts":     results,
		"page":      page,
		"page_size": pageSize,
	})

	// Increment view counts in background — doesn't block the HTTP response
	go func(ids []uint, db *gorm.DB) {
		if len(ids) > 0 {
			db.Model(&models.Post{}).
				Where("id IN ?", ids).
				UpdateColumn("view_count", gorm.Expr("view_count + ?", 1))
		}
	}(postIDsToView, h.DB)
}

// GetUserPosts returns posts by a user
func (h *PostHandler) GetUserPosts(c *gin.Context) {
	userID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	var posts []models.Post
	h.DB.Where("user_id = ?", userID).
		Preload("User").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&posts)

	var results []gin.H
	for _, p := range posts {
		results = append(results, gin.H{
			"id":            p.ID,
			"content":       p.Content,
			"media_url":     p.MediaURL,
			"media_type":    p.MediaType,
			"thumbnail":     p.Thumbnail,
			"duration":      p.Duration,
			"view_count":    p.ViewCount,
			"like_count":    p.LikeCount,
			"comment_count": p.CommentCount,
			"created_at":    p.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"posts":     results,
		"page":      page,
		"page_size": pageSize,
	})
}

// DeletePost deletes a post
func (h *PostHandler) DeletePost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	var post models.Post
	if err := h.DB.First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	// Check ownership
	if post.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only delete your own posts"})
		return
	}

	if err := h.DB.Delete(&post).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete post"})
		return
	}

	// Update post count
	h.DB.Model(&models.User{}).Where("id = ?", userID).UpdateColumn("post_count", gorm.Expr("post_count - ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Post deleted successfully"})
}

// LikePost likes a post
func (h *PostHandler) LikePost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	// Check if already liked
	var existingLike models.Like
	if h.DB.Where("user_id = ? AND post_id = ?", userID, postID).First(&existingLike).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Already liked"})
		return
	}

	like := models.Like{
		PostID: uint(postID),
		UserID: userID,
	}

	if err := h.DB.Create(&like).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like post"})
		return
	}

	// Update like count
	h.DB.Model(&models.Post{}).Where("id = ?", postID).UpdateColumn("like_count", gorm.Expr("like_count + ?", 1))

	// Get post to find owner and updated like count
	var post models.Post
	h.DB.First(&post, postID)

	// Broadcast like via WebSocket
	websocket.GetHub().BroadcastPostLike(uint(postID), userID, true, post.LikeCount+1)

	// Create notification
	if post.UserID != userID {
		notification := models.Notification{
			UserID:  post.UserID,
			Type:    "like",
			ActorID: userID,
			PostID:  &post.ID,
			Message: "liked your post",
		}
		h.DB.Create(&notification)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post liked successfully"})
}

// UnlikePost unlikes a post
func (h *PostHandler) UnlikePost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	postID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	result := h.DB.Where("user_id = ? AND post_id = ?", userID, postID).Delete(&models.Like{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike post"})
		return
	}

	if result.RowsAffected > 0 {
		h.DB.Model(&models.Post{}).Where("id = ?", postID).UpdateColumn("like_count", gorm.Expr("like_count - ?", 1))

		// Get updated like count
		var post models.Post
		h.DB.First(&post, postID)

		// Broadcast unlike via WebSocket
		websocket.GetHub().BroadcastPostLike(uint(postID), userID, false, post.LikeCount)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post unliked successfully"})
}

// GetTrending returns trending posts
func (h *PostHandler) GetTrending(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	var posts []models.Post
	h.DB.Where("is_public = ?", true).
		Preload("User").
		Order("like_count DESC, view_count DESC, created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&posts)

	var results []gin.H
	for _, p := range posts {
		results = append(results, gin.H{
			"id":            p.ID,
			"content":       p.Content,
			"media_url":     p.MediaURL,
			"media_type":    p.MediaType,
			"thumbnail":     p.Thumbnail,
			"duration":      p.Duration,
			"view_count":    p.ViewCount,
			"like_count":    p.LikeCount,
			"comment_count": p.CommentCount,
			"created_at":    p.CreatedAt,
			"user": gin.H{
				"id":            p.User.ID,
				"username":      p.User.Username,
				"profile_image": p.User.ProfileImage,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"posts":     results,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetPostsByHashtag returns posts containing a specific hashtag
func (h *PostHandler) GetPostsByHashtag(c *gin.Context) {
	hashtag := c.Param("hashtag")
	if hashtag == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Hashtag is required"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	hashtagPattern := "%#" + hashtag + "%"

	var posts []models.Post
	h.DB.Where("is_public = ? AND hash_tags LIKE ?", true, hashtagPattern).
		Preload("User").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&posts)

	var results []gin.H
	currentUserID := utils.GetCurrentUserID(c)
	for _, p := range posts {
		var isLiked bool
		if currentUserID > 0 {
			var like models.Like
			isLiked = h.DB.Where("user_id = ? AND post_id = ?", currentUserID, p.ID).First(&like).Error == nil
		}

		results = append(results, gin.H{
			"id":            p.ID,
			"content":       p.Content,
			"media_url":     p.MediaURL,
			"media_type":    p.MediaType,
			"thumbnail":     p.Thumbnail,
			"duration":      p.Duration,
			"view_count":    p.ViewCount,
			"like_count":    p.LikeCount,
			"comment_count": p.CommentCount,
			"created_at":    p.CreatedAt,
			"user": gin.H{
				"id":            p.User.ID,
				"username":      p.User.Username,
				"full_name":     p.User.FullName,
				"profile_image": p.User.ProfileImage,
				"is_verified":   p.User.IsVerified,
			},
			"is_liked": isLiked,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"posts":     results,
		"page":      page,
		"page_size": pageSize,
		"hashtag":   hashtag,
	})
}

// GetTrendingHashtags returns trending hashtags
func (h *PostHandler) GetTrendingHashtags(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	type hashtagCount struct {
		Hashtag string
		Count   int64
	}

	var hashtags []hashtagCount
	h.DB.Table("posts").
		Select("substring_index(substring_index(hash_tags, ',', 1), ',', -1) as hashtag, count(*) as count").
		Where("hash_tags != '' AND hash_tags IS NOT NULL").
		Group("hashtag").
		Order("count DESC").
		Limit(limit).
		Scan(&hashtags)

	var results []gin.H
	for _, h := range hashtags {
		results = append(results, gin.H{
			"tag":   h.Hashtag,
			"count": h.Count,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"hashtags": results,
	})
}
