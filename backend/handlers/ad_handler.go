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

type AdHandler struct {
	DB *gorm.DB
}

func NewAdHandler(db *gorm.DB) *AdHandler {
	return &AdHandler{DB: db}
}

// CreateAd creates a new advertisement
func (h *AdHandler) CreateAd(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	// Use raw map to avoid time.Time parsing issues
	var raw map[string]interface{}
	if err := c.ShouldBindJSON(&raw); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	title, _ := raw["title"].(string)
	if title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title is required"})
		return
	}

	budget := 0.0
	switch v := raw["budget"].(type) {
	case float64:
		budget = v
	case string:
		budget, _ = strconv.ParseFloat(v, 64)
	}

	ad := models.Ad{
		AdvertiserID:    userID,
		Title:           title,
		Description:     getString(raw, "description"),
		MediaURL:        getString(raw, "media_url"),
		MediaType:       getString(raw, "media_type"),
		TargetURL:       getString(raw, "target_url"),
		Budget:          budget,
		TargetAge:       getString(raw, "target_age"),
		TargetGender:    getString(raw, "target_gender"),
		TargetInterests: getString(raw, "target_interests"),
		Status:          "active",
		StartDate:       time.Now(),
	}

	// Optional end_date
	if endStr, ok := raw["end_date"].(string); ok && endStr != "" {
		if t, err := time.Parse(time.RFC3339, endStr); err == nil {
			ad.EndDate = &t
		}
	}

	if err := h.DB.Create(&ad).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create ad"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Ad created successfully",
		"ad":      ad,
	})
}

func getString(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

// GetAds returns ads for the current user
func (h *AdHandler) GetMyAds(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var ads []models.Ad
	h.DB.Where("advertiser_id = ?", userID).
		Order("created_at DESC").
		Find(&ads)

	c.JSON(http.StatusOK, gin.H{"ads": ads})
}

// GetFeedAds returns active ads for the feed (for ad injection)
func (h *AdHandler) GetFeedAds(c *gin.Context) {
	var ads []models.Ad
	now := time.Now()
	h.DB.Where("status = ? AND start_date <= ?", "active", now).
		Preload("Advertiser").
		Order("RANDOM()").
		Limit(3).
		Find(&ads)

	var results []gin.H
	for _, ad := range ads {
		results = append(results, gin.H{
			"id":          ad.ID,
			"title":       ad.Title,
			"description": ad.Description,
			"media_url":   ad.MediaURL,
			"media_type":  ad.MediaType,
			"target_url":  ad.TargetURL,
			"advertiser": gin.H{
				"id":       ad.Advertiser.ID,
				"username": ad.Advertiser.Username,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{"ads": results})
}

// TrackAdImpression records an ad impression
func (h *AdHandler) TrackAdImpression(c *gin.Context) {
	adID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ad ID"})
		return
	}

	h.DB.Model(&models.Ad{}).Where("id = ?", adID).
		UpdateColumn("impression_count", gorm.Expr("impression_count + ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Impression tracked"})
}

// TrackAdClick records an ad click
func (h *AdHandler) TrackAdClick(c *gin.Context) {
	adID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ad ID"})
		return
	}

	h.DB.Model(&models.Ad{}).Where("id = ?", adID).
		UpdateColumn("click_count", gorm.Expr("click_count + ?", 1))

	c.JSON(http.StatusOK, gin.H{"message": "Click tracked"})
}

// UpdateAd updates an advertisement
func (h *AdHandler) UpdateAd(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	adID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ad ID"})
		return
	}

	var ad models.Ad
	if err := h.DB.First(&ad, adID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Ad not found"})
		return
	}
	if ad.AdvertiserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
		return
	}

	var input struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		Status      string `json:"status"`
		Budget      float64 `json:"budget"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{}
	if input.Title != "" {
		updates["title"] = input.Title
	}
	if input.Description != "" {
		updates["description"] = input.Description
	}
	if input.Status != "" {
		updates["status"] = input.Status
	}
	if input.Budget > 0 {
		updates["budget"] = input.Budget
	}

	h.DB.Model(&ad).Updates(updates)
	c.JSON(http.StatusOK, gin.H{"message": "Ad updated", "ad": ad})
}

// DeleteAd deletes an advertisement
func (h *AdHandler) DeleteAd(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	adID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ad ID"})
		return
	}

	var ad models.Ad
	if err := h.DB.First(&ad, adID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Ad not found"})
		return
	}
	if ad.AdvertiserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
		return
	}

	h.DB.Delete(&ad)
	c.JSON(http.StatusOK, gin.H{"message": "Ad deleted"})
}

// GetAdStats returns analytics for an ad
func (h *AdHandler) GetAdStats(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	adID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ad ID"})
		return
	}

	var ad models.Ad
	if err := h.DB.First(&ad, adID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Ad not found"})
		return
	}
	if ad.AdvertiserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
		return
	}

	ctr := 0.0
	if ad.ImpressionCount > 0 {
		ctr = float64(ad.ClickCount) / float64(ad.ImpressionCount) * 100
	}

	c.JSON(http.StatusOK, gin.H{
		"ad_id":            ad.ID,
		"title":            ad.Title,
		"status":           ad.Status,
		"budget":           ad.Budget,
		"spent_amount":     ad.SpentAmount,
		"impression_count": ad.ImpressionCount,
		"click_count":      ad.ClickCount,
		"ctr":              ctr,
		"start_date":       ad.StartDate,
		"end_date":         ad.EndDate,
	})
}
