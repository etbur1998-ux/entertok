package handlers

import (
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// UserHandler handles user-related endpoints
type UserHandler struct {
	DB *gorm.DB
}

// GetUser returns a user by ID
func (h *UserHandler) GetUser(c *gin.Context) {
	userID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	currentUserID := utils.GetCurrentUserID(c)
	var isFollowing bool
	if currentUserID > 0 {
		var follow models.Follow
		isFollowing = h.DB.Where("follower_id = ? AND following_id = ?", currentUserID, userID).First(&follow).Error == nil
	}

	c.JSON(http.StatusOK, gin.H{
		"id":              user.ID,
		"username":        user.Username,
		"full_name":       user.FullName,
		"bio":             user.Bio,
		"profile_image":   user.ProfileImage,
		"cover_image":     user.CoverImage,
		"website":         user.Website,
		"location":        user.Location,
		"is_verified":     user.IsVerified,
		"is_private":      user.IsPrivate,
		"post_count":      user.PostCount,
		"follower_count":  user.FollowerCount,
		"following_count": user.FollowingCount,
		"is_following":    isFollowing,
		"created_at":      user.CreatedAt,
	})
}

// UpdateProfile updates the current user's profile
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		FullName     string `json:"full_name"`
		Bio          string `json:"bio"`
		Phone        string `json:"phone"`
		Website      string `json:"website"`
		Location     string `json:"location"`
		ProfileImage string `json:"profile_image"`
		CoverImage   string `json:"cover_image"`
		Gender       string `json:"gender"`
		IsPrivate    *bool  `json:"is_private"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := make(map[string]interface{})

	if input.FullName != "" {
		updates["full_name"] = input.FullName
	}
	if input.Bio != "" {
		updates["bio"] = input.Bio
	}
	if input.Phone != "" {
		updates["phone"] = input.Phone
	}
	if input.Website != "" {
		updates["website"] = input.Website
	}
	if input.Location != "" {
		updates["location"] = input.Location
	}
	if input.ProfileImage != "" {
		updates["profile_image"] = input.ProfileImage
	}
	if input.CoverImage != "" {
		updates["cover_image"] = input.CoverImage
	}
	if input.Gender != "" {
		updates["gender"] = input.Gender
	}
	if input.IsPrivate != nil {
		updates["is_private"] = *input.IsPrivate
	}

	if err := h.DB.Model(&models.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile"})
		return
	}

	var user models.User
	h.DB.First(&user, userID)

	c.JSON(http.StatusOK, gin.H{
		"message": "Profile updated successfully",
		"user": gin.H{
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
			"gender":          user.Gender,
			"is_private":      user.IsPrivate,
		},
	})
}

// FollowUser follows a user
func (h *UserHandler) FollowUser(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	followID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if userID == uint(followID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot follow yourself"})
		return
	}

	// Check if already following
	var existingFollow models.Follow
	if h.DB.Where("follower_id = ? AND following_id = ?", userID, followID).First(&existingFollow).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Already following this user"})
		return
	}

	// Create follow
	follow := models.Follow{
		FollowerID:  userID,
		FollowingID: uint(followID),
	}

	if err := h.DB.Create(&follow).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to follow user"})
		return
	}

	// Update follower/following counts
	h.DB.Model(&models.User{}).Where("id = ?", userID).UpdateColumn("following_count", gorm.Expr("following_count + ?", 1))
	h.DB.Model(&models.User{}).Where("id = ?", followID).UpdateColumn("follower_count", gorm.Expr("follower_count + ?", 1))

	// Create notification
	notification := models.Notification{
		UserID:  uint(followID),
		Type:    "follow",
		ActorID: userID,
		Message: "started following you",
	}
	h.DB.Create(&notification)

	// Process boost reward if the followed user has an active boost campaign
	ProcessBoostReward(h.DB, userID, uint(followID))

	c.JSON(http.StatusOK, gin.H{"message": "Successfully followed user"})
}

// UnfollowUser unfollows a user
func (h *UserHandler) UnfollowUser(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	followID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	result := h.DB.Where("follower_id = ? AND following_id = ?", userID, followID).Delete(&models.Follow{})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unfollow user"})
		return
	}

	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Not following this user"})
		return
	}

	// Update follower/following counts
	h.DB.Model(&models.User{}).Where("id = ?", userID).UpdateColumn("following_count", gorm.Expr("following_count - ?", 1))
	h.DB.Model(&models.User{}).Where("id = ?", followID).UpdateColumn("follower_count", gorm.Expr("follower_count - ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Successfully unfollowed user"})
}

// GetFollowers returns followers of a user
func (h *UserHandler) GetFollowers(c *gin.Context) {
	userID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var follows []models.Follow
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	h.DB.Where("following_id = ?", userID).
		Preload("Follower").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&follows)

	var followers []gin.H
	for _, f := range follows {
		followers = append(followers, gin.H{
			"id":           f.Follower.ID,
			"username":     f.Follower.Username,
			"full_name":    f.Follower.FullName,
			"profile_image": f.Follower.ProfileImage,
			"is_verified":  f.Follower.IsVerified,
			"created_at":  f.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"followers": followers,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetFollowing returns users that a user is following
func (h *UserHandler) GetFollowing(c *gin.Context) {
	userID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var follows []models.Follow
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	h.DB.Where("follower_id = ?", userID).
		Preload("Following").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&follows)

	var following []gin.H
	for _, f := range follows {
		following = append(following, gin.H{
			"id":           f.Following.ID,
			"username":     f.Following.Username,
			"full_name":    f.Following.FullName,
			"profile_image": f.Following.ProfileImage,
			"is_verified":  f.Following.IsVerified,
			"created_at":  f.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"following": following,
		"page":      page,
		"page_size": pageSize,
	})
}

// SearchUsers searches for users by username
func (h *UserHandler) SearchUsers(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Search query required"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	// Get current user ID to exclude from search
	currentUserID := utils.GetCurrentUserID(c)

	var users []models.User
	h.DB.Where("id != ? AND (username LIKE ? OR full_name LIKE ?)", currentUserID, "%"+query+"%", "%"+query+"%").
		Order("follower_count DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&users)

	var results []gin.H
	for _, u := range users {
		results = append(results, gin.H{
			"id":              u.ID,
			"username":        u.Username,
			"full_name":       u.FullName,
			"profile_image":   u.ProfileImage,
			"is_verified":     u.IsVerified,
			"follower_count":  u.FollowerCount,
			"following_count": u.FollowingCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"users":     results,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetSuggestions returns suggested users to follow
func (h *UserHandler) GetSuggestions(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	// Get users that current user is not following
	var users []models.User
	subQuery := h.DB.Model(&models.Follow{}).Where("follower_id = ?", userID).Select("following_id")
	h.DB.Where("id NOT IN (?) AND id != ?", subQuery, userID).
		Order("follower_count DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&users)

	var suggestions []gin.H
	for _, u := range users {
		suggestions = append(suggestions, gin.H{
			"id":              u.ID,
			"username":        u.Username,
			"full_name":       u.FullName,
			"profile_image":   u.ProfileImage,
			"is_verified":     u.IsVerified,
			"follower_count":  u.FollowerCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"suggestions": suggestions,
		"page":        page,
		"page_size":   pageSize,
	})
}
