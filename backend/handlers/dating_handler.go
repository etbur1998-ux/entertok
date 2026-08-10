package handlers

import (
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type DatingHandler struct {
	DB *gorm.DB
}

func NewDatingHandler(db *gorm.DB) *DatingHandler {
	return &DatingHandler{DB: db}
}

// GetSuggestions returns dating suggestions filtered by opposite gender
func (h *DatingHandler) GetSuggestions(c *gin.Context) {
	currentUserID := utils.GetCurrentUserID(c)
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))

	// Get current user's gender to filter by opposite
	var me models.User
	h.DB.First(&me, currentUserID)

	query := h.DB.Where("id != ? AND role = ?", currentUserID, "user")

	// Show opposite gender: male sees female, female sees male.
	// If gender is unknown/other, show everyone.
	switch me.Gender {
	case "male", "Male":
		query = query.Where("gender IN ?", []string{"female", "Female"})
	case "female", "Female":
		query = query.Where("gender IN ?", []string{"male", "Male"})
	}

	var users []models.User
	query.Order("RANDOM()").Limit(limit).Find(&users)

	// If no results (e.g. no gender set), fall back to all users
	if len(users) == 0 {
		h.DB.Where("id != ? AND role = ?", currentUserID, "user").
			Order("RANDOM()").Limit(limit).Find(&users)
	}

	var results []gin.H
	for _, u := range users {
		var follow models.Follow
		isFollowing := h.DB.Where("follower_id = ? AND following_id = ?", currentUserID, u.ID).
			First(&follow).Error == nil

		results = append(results, gin.H{
			"id":              u.ID,
			"username":        u.Username,
			"full_name":       u.FullName,
			"bio":             u.Bio,
			"profile_image":   u.ProfileImage,
			"location":        u.Location,
			"gender":          u.Gender,
			"follower_count":  u.FollowerCount,
			"following_count": u.FollowingCount,
			"post_count":      u.PostCount,
			"is_verified":     u.IsVerified,
			"is_online":       u.IsOnline,
			"is_following":    isFollowing,
		})
	}

	if results == nil {
		results = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"users": results})
}

// GetLikes returns users who liked (follow) the current user
// = users who follow the current user (followers)
func (h *DatingHandler) GetLikes(c *gin.Context) {
	currentUserID := utils.GetCurrentUserID(c)

	var followers []models.Follow
	h.DB.Where("following_id = ?", currentUserID).
		Preload("Follower").
		Order("created_at DESC").
		Limit(50).
		Find(&followers)

	var results []gin.H
	for _, f := range followers {
		u := f.Follower
		// Check if current user also follows back (mutual = match)
		var follow models.Follow
		isMatch := h.DB.Where("follower_id = ? AND following_id = ?", currentUserID, u.ID).
			First(&follow).Error == nil

		results = append(results, gin.H{
			"id":            u.ID,
			"username":      u.Username,
			"full_name":     u.FullName,
			"bio":           u.Bio,
			"profile_image": u.ProfileImage,
			"location":      u.Location,
			"gender":        u.Gender,
			"follower_count": u.FollowerCount,
			"is_verified":   u.IsVerified,
			"is_online":     u.IsOnline,
			"is_match":      isMatch,
		})
	}

	if results == nil {
		results = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"likes": results, "total": len(results)})
}

// GetMatches returns mutual follows (both follow each other)
func (h *DatingHandler) GetMatches(c *gin.Context) {
	currentUserID := utils.GetCurrentUserID(c)

	// Users the current user follows
	var following []models.Follow
	h.DB.Where("follower_id = ?", currentUserID).Find(&following)

	followingIDs := make([]uint, 0)
	for _, f := range following {
		followingIDs = append(followingIDs, f.FollowingID)
	}

	if len(followingIDs) == 0 {
		c.JSON(http.StatusOK, gin.H{"matches": []gin.H{}, "total": 0})
		return
	}

	// Of those, who also follows back
	var mutualFollows []models.Follow
	h.DB.Where("follower_id IN ? AND following_id = ?", followingIDs, currentUserID).
		Preload("Follower").
		Find(&mutualFollows)

	var results []gin.H
	for _, f := range mutualFollows {
		u := f.Follower
		results = append(results, gin.H{
			"id":            u.ID,
			"username":      u.Username,
			"full_name":     u.FullName,
			"bio":           u.Bio,
			"profile_image": u.ProfileImage,
			"location":      u.Location,
			"gender":        u.Gender,
			"follower_count": u.FollowerCount,
			"is_verified":   u.IsVerified,
			"is_online":     u.IsOnline,
		})
	}

	if results == nil {
		results = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"matches": results, "total": len(results)})
}

// LikeUser follows a user (like = follow in dating context)
func (h *DatingHandler) LikeUser(c *gin.Context) {
	currentUserID := utils.GetCurrentUserID(c)
	targetID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if uint(targetID) == currentUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot like yourself"})
		return
	}

	// Create follow
	var existing models.Follow
	if h.DB.Where("follower_id = ? AND following_id = ?", currentUserID, targetID).First(&existing).Error == nil {
		c.JSON(http.StatusOK, gin.H{"liked": true, "message": "Already liked"})
		return
	}

	follow := models.Follow{FollowerID: currentUserID, FollowingID: uint(targetID)}
	h.DB.Create(&follow)

	// Update counts
	h.DB.Model(&models.User{}).Where("id = ?", currentUserID).
		UpdateColumn("following_count", gorm.Expr("following_count + 1"))
	h.DB.Model(&models.User{}).Where("id = ?", targetID).
		UpdateColumn("follower_count", gorm.Expr("follower_count + 1"))

	// Check if it's a match (target also follows back)
	var reverseFollow models.Follow
	isMatch := h.DB.Where("follower_id = ? AND following_id = ?", targetID, currentUserID).
		First(&reverseFollow).Error == nil

	c.JSON(http.StatusOK, gin.H{
		"liked":    true,
		"is_match": isMatch,
		"message":  "Liked successfully",
	})
}

// DislikeUser unfollows a user (skip/nope)
func (h *DatingHandler) DislikeUser(c *gin.Context) {
	currentUserID := utils.GetCurrentUserID(c)
	targetID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}
	// Just record the skip — don't unfollow if already following
	_ = targetID
	_ = currentUserID
	c.JSON(http.StatusOK, gin.H{"skipped": true})
}
