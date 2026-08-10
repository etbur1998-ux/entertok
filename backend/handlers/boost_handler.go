package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// BoostHandler manages paid follower boost campaigns
type BoostHandler struct {
	DB *gorm.DB
}

func NewBoostHandler(db *gorm.DB) *BoostHandler {
	return &BoostHandler{DB: db}
}

const (
	PricePerFollower = 2.00  // buyer pays 2 Birr per follower
	EarnPerFollower  = 1.70  // follower earns 1.70 Birr
	FeePerFollower   = 0.30  // platform fee 0.30 Birr
)

// getOrCreateWallet ensures a wallet exists for a user
func (h *BoostHandler) getOrCreateWallet(userID uint) (*models.Wallet, error) {
	var wallet models.Wallet
	err := h.DB.Where("user_id = ?", userID).First(&wallet).Error
	if err == gorm.ErrRecordNotFound {
		wallet = models.Wallet{
			UserID:        userID,
			Balance:       0,
			Currency:      "Birr",
			WalletAddress: generateWalletAddress(),
			IsActive:      true,
		}
		if err := h.DB.Create(&wallet).Error; err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	return &wallet, nil
}

// CreateBoost — user creates a paid follower boost campaign
// POST /boost
func (h *BoostHandler) CreateBoost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		TargetFollowers int `json:"target_followers" binding:"required,min=1,max=10000"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	totalCost := float64(input.TargetFollowers) * PricePerFollower

	// Check wallet balance
	wallet, err := h.getOrCreateWallet(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Wallet error"})
		return
	}
	if wallet.Balance < totalCost {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":    fmt.Sprintf("Insufficient balance. Need %.2f Birr, have %.2f Birr", totalCost, wallet.Balance),
			"required": totalCost,
			"balance":  wallet.Balance,
		})
		return
	}

	// Check no active campaign exists
	var existing models.BoostCampaign
	if h.DB.Where("user_id = ? AND status = ?", userID, "active").First(&existing).Error == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "You already have an active boost campaign", "campaign_id": existing.ID})
		return
	}

	// Deduct total cost from wallet (held in escrow)
	h.DB.Model(wallet).UpdateColumn("balance", gorm.Expr("balance - ?", totalCost))

	// Record escrow deduction transaction
	h.DB.Create(&models.Transaction{
		WalletID:    wallet.ID,
		Type:        "boost_escrow",
		Amount:      -totalCost,
		Fee:         0,
		Description: fmt.Sprintf("Boost escrow: %d followers × 2.00 Birr", input.TargetFollowers),
		ReferenceID: generateTxRef(),
		Status:      "completed",
	})

	// Create campaign
	campaign := models.BoostCampaign{
		UserID:           userID,
		TargetFollowers:  input.TargetFollowers,
		PricePerFollower: PricePerFollower,
		EarnPerFollower:  EarnPerFollower,
		FeePerFollower:   FeePerFollower,
		TotalCost:        totalCost,
		Status:           "active",
	}
	h.DB.Create(&campaign)

	c.JSON(http.StatusCreated, gin.H{
		"message":          "Boost campaign created",
		"campaign_id":      campaign.ID,
		"target_followers": campaign.TargetFollowers,
		"total_cost":       campaign.TotalCost,
		"price_per_follower": PricePerFollower,
		"earn_per_follower": EarnPerFollower,
		"fee_per_follower":  FeePerFollower,
		"status":           campaign.Status,
	})
}

// GetMyBoosts — list user's own boost campaigns
// GET /boost/my
func (h *BoostHandler) GetMyBoosts(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var campaigns []models.BoostCampaign
	h.DB.Where("user_id = ?", userID).
		Order("created_at DESC").
		Find(&campaigns)

	results := make([]gin.H, 0, len(campaigns))
	for _, cam := range campaigns {
		results = append(results, gin.H{
			"id":               cam.ID,
			"target_followers": cam.TargetFollowers,
			"followers_gained": cam.FollowersGained,
			"total_cost":       cam.TotalCost,
			"total_spent":      cam.TotalSpent,
			"price_per_follower": cam.PricePerFollower,
			"earn_per_follower":  cam.EarnPerFollower,
			"status":           cam.Status,
			"progress_pct":     func() float64 {
				if cam.TargetFollowers == 0 { return 0 }
				return float64(cam.FollowersGained) / float64(cam.TargetFollowers) * 100
			}(),
			"created_at": cam.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"campaigns": results})
}

// GetActiveBoostedUsers — returns list of users with active boost campaigns
// GET /boost/active  (used by Follow action to check if reward applies)
func (h *BoostHandler) GetActiveBoostedUsers(c *gin.Context) {
	var campaigns []models.BoostCampaign
	h.DB.Where("status = ?", "active").
		Preload("User").
		Find(&campaigns)

	results := make([]gin.H, 0, len(campaigns))
	for _, cam := range campaigns {
		results = append(results, gin.H{
			"user_id":          cam.UserID,
			"campaign_id":      cam.ID,
			"username":         cam.User.Username,
			"profile_image":    cam.User.ProfileImage,
			"followers_needed": cam.TargetFollowers - cam.FollowersGained,
			"earn_per_follow":  cam.EarnPerFollower,
		})
	}

	c.JSON(http.StatusOK, gin.H{"boosted_users": results})
}

// PauseBoost — pause an active campaign
// POST /boost/:id/pause
func (h *BoostHandler) PauseBoost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)

	var campaign models.BoostCampaign
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&campaign).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Campaign not found"})
		return
	}
	h.DB.Model(&campaign).Update("status", "paused")
	c.JSON(http.StatusOK, gin.H{"message": "Campaign paused"})
}

// CancelBoost — cancel campaign and refund remaining balance
// POST /boost/:id/cancel
func (h *BoostHandler) CancelBoost(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)

	var campaign models.BoostCampaign
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&campaign).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Campaign not found"})
		return
	}
	if campaign.Status == "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot cancel a completed campaign"})
		return
	}

	// Calculate refund (unused followers)
	remaining := campaign.TargetFollowers - campaign.FollowersGained
	refund := float64(remaining) * PricePerFollower

	h.DB.Model(&campaign).Update("status", "cancelled")

	// Refund unused escrow
	if refund > 0 {
		wallet, _ := h.getOrCreateWallet(userID)
		h.DB.Model(wallet).UpdateColumn("balance", gorm.Expr("balance + ?", refund))
		h.DB.Create(&models.Transaction{
			WalletID:    wallet.ID,
			Type:        "boost_refund",
			Amount:      refund,
			Fee:         0,
			Description: fmt.Sprintf("Boost refund: %d unused followers × 2.00 Birr", remaining),
			ReferenceID: generateTxRef(),
			Status:      "completed",
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Campaign cancelled",
		"refund":  refund,
	})
}

// ProcessBoostReward — called internally when a user follows someone with an active boost
// Returns how much the follower earned (0 if no boost applies)
func ProcessBoostReward(db *gorm.DB, followerID, followingID uint) float64 {
	// Check if the followed user has an active campaign
	var campaign models.BoostCampaign
	err := db.Where("user_id = ? AND status = ?", followingID, "active").First(&campaign).Error
	if err != nil {
		return 0 // no active campaign
	}

	// Check follower hasn't already been rewarded for this campaign
	var existing models.BoostReward
	if db.Where("campaign_id = ? AND follower_id = ?", campaign.ID, followerID).First(&existing).Error == nil {
		return 0 // already rewarded
	}

	// Check campaign still has room
	if campaign.FollowersGained >= campaign.TargetFollowers {
		// Auto-complete campaign
		db.Model(&campaign).Update("status", "completed")
		return 0
	}

	now := time.Now()

	// Credit follower wallet
	var followerWallet models.Wallet
	if db.Where("user_id = ?", followerID).First(&followerWallet).Error == gorm.ErrRecordNotFound {
		followerWallet = models.Wallet{
			UserID:        followerID,
			Balance:       0,
			Currency:      "Birr",
			WalletAddress: generateWalletAddress(),
			IsActive:      true,
		}
		db.Create(&followerWallet)
	}
	db.Model(&followerWallet).UpdateColumn("balance", gorm.Expr("balance + ?", EarnPerFollower))
	db.Create(&models.Transaction{
		WalletID:    followerWallet.ID,
		Type:        "boost_earn",
		Amount:      EarnPerFollower,
		Fee:         0,
		Description: fmt.Sprintf("Earned for following @%d (boost reward)", followingID),
		ReferenceID: generateTxRef(),
		Status:      "completed",
		CreatedAt:   now,
	})

	// Record reward
	reward := models.BoostReward{
		CampaignID:    campaign.ID,
		FollowerID:    followerID,
		BoostedUserID: followingID,
		EarnAmount:    EarnPerFollower,
		FeeAmount:     FeePerFollower,
		Status:        "paid",
		PaidAt:        &now,
	}
	db.Create(&reward)

	// Update campaign stats
	db.Model(&campaign).Updates(map[string]interface{}{
		"followers_gained": gorm.Expr("followers_gained + 1"),
		"total_spent":      gorm.Expr("total_spent + ?", PricePerFollower),
	})

	// Auto-complete if target reached
	var updated models.BoostCampaign
	db.First(&updated, campaign.ID)
	if updated.FollowersGained >= updated.TargetFollowers {
		db.Model(&updated).Update("status", "completed")
	}

	// Send notification to follower
	db.Create(&models.Notification{
		UserID:  followerID,
		Type:    "boost_reward",
		ActorID: followingID,
		Message: fmt.Sprintf("You earned %.2f Birr for following a boosted user!", EarnPerFollower),
	})

	return EarnPerFollower
}

// GetBoostStats — user's boost earnings summary
// GET /boost/stats
func (h *BoostHandler) GetBoostStats(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	// Total earned by following boosted users
	var totalEarned float64
	h.DB.Model(&models.BoostReward{}).
		Where("follower_id = ? AND status = ?", userID, "paid").
		Select("COALESCE(SUM(earn_amount), 0)").Scan(&totalEarned)

	var rewardCount int64
	h.DB.Model(&models.BoostReward{}).
		Where("follower_id = ? AND status = ?", userID, "paid").
		Count(&rewardCount)

	// My campaigns stats
	var totalSpentOnBoost float64
	var totalFollowersGained int64
	h.DB.Model(&models.BoostCampaign{}).
		Where("user_id = ?", userID).
		Select("COALESCE(SUM(total_spent), 0)").Scan(&totalSpentOnBoost)
	h.DB.Model(&models.BoostCampaign{}).
		Where("user_id = ?", userID).
		Select("COALESCE(SUM(followers_gained), 0)").Scan(&totalFollowersGained)

	// Active campaign
	var activeCampaign *gin.H
	var cam models.BoostCampaign
	if h.DB.Where("user_id = ? AND status = ?", userID, "active").First(&cam).Error == nil {
		remaining := cam.TargetFollowers - cam.FollowersGained
		ac := gin.H{
			"id":               cam.ID,
			"target_followers": cam.TargetFollowers,
			"followers_gained": cam.FollowersGained,
			"remaining":        remaining,
			"total_cost":       cam.TotalCost,
			"total_spent":      cam.TotalSpent,
			"progress_pct":     float64(cam.FollowersGained) / float64(cam.TargetFollowers) * 100,
		}
		activeCampaign = &ac
	}

	c.JSON(http.StatusOK, gin.H{
		"total_earned_from_following": totalEarned,
		"rewards_received":            rewardCount,
		"total_spent_on_boost":        totalSpentOnBoost,
		"total_followers_gained":      totalFollowersGained,
		"price_per_follower":          PricePerFollower,
		"earn_per_follow":             EarnPerFollower,
		"platform_fee":                FeePerFollower,
		"active_campaign":             activeCampaign,
	})
}

// ─── Admin endpoints ──────────────────────────────────────────────────────────

// AdminGetAllBoosts — admin: see all boost campaigns
func (h *BoostHandler) AdminGetAllBoosts(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	status := c.Query("status")

	query := h.DB.Model(&models.BoostCampaign{}).Preload("User")
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var campaigns []models.BoostCampaign
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&campaigns)

	results := make([]gin.H, 0, len(campaigns))
	for _, cam := range campaigns {
		results = append(results, gin.H{
			"id":               cam.ID,
			"user_id":          cam.UserID,
			"username":         cam.User.Username,
			"full_name":        cam.User.FullName,
			"profile_image":    cam.User.ProfileImage,
			"target_followers": cam.TargetFollowers,
			"followers_gained": cam.FollowersGained,
			"total_cost":       cam.TotalCost,
			"total_spent":      cam.TotalSpent,
			"price_per_follower": cam.PricePerFollower,
			"earn_per_follower":  cam.EarnPerFollower,
			"fee_per_follower":   cam.FeePerFollower,
			"status":           cam.Status,
			"progress_pct": func() float64 {
				if cam.TargetFollowers == 0 { return 0 }
				return float64(cam.FollowersGained) / float64(cam.TargetFollowers) * 100
			}(),
			"platform_revenue": float64(cam.FollowersGained) * FeePerFollower,
			"created_at":       cam.CreatedAt,
		})
	}

	// Overall platform stats
	var totalRevenue float64
	h.DB.Model(&models.BoostReward{}).
		Select("COALESCE(SUM(fee_amount), 0)").Scan(&totalRevenue)
	var totalRewards int64
	h.DB.Model(&models.BoostReward{}).Count(&totalRewards)
	var totalPaidOut float64
	h.DB.Model(&models.BoostReward{}).
		Select("COALESCE(SUM(earn_amount), 0)").Scan(&totalPaidOut)

	c.JSON(http.StatusOK, gin.H{
		"campaigns":       results,
		"total":           total,
		"platform_stats": gin.H{
			"total_revenue":   totalRevenue,
			"total_paid_out":  totalPaidOut,
			"total_rewards":   totalRewards,
			"price_per_follow": PricePerFollower,
			"earn_per_follow": EarnPerFollower,
			"fee_per_follow":  FeePerFollower,
		},
	})
}

// AdminGetBoostRewards — admin: see all boost reward payments
func (h *BoostHandler) AdminGetBoostRewards(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	var total int64
	h.DB.Model(&models.BoostReward{}).Count(&total)

	var rewards []models.BoostReward
	h.DB.Preload("Follower").Preload("BoostedUser").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&rewards)

	results := make([]gin.H, 0, len(rewards))
	for _, r := range rewards {
		results = append(results, gin.H{
			"id":           r.ID,
			"campaign_id":  r.CampaignID,
			"follower": gin.H{
				"id": r.Follower.ID, "username": r.Follower.Username,
				"profile_image": r.Follower.ProfileImage,
			},
			"boosted_user": gin.H{
				"id": r.BoostedUser.ID, "username": r.BoostedUser.Username,
				"profile_image": r.BoostedUser.ProfileImage,
			},
			"earn_amount": r.EarnAmount,
			"fee_amount":  r.FeeAmount,
			"status":      r.Status,
			"paid_at":     r.PaidAt,
			"created_at":  r.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"rewards": results, "total": total})
}

// AdminForceStopBoost — admin: force stop a campaign
func (h *BoostHandler) AdminForceStopBoost(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var campaign models.BoostCampaign
	if err := h.DB.First(&campaign, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Campaign not found"})
		return
	}
	h.DB.Model(&campaign).Update("status", "cancelled")
	c.JSON(http.StatusOK, gin.H{"message": "Campaign force-stopped"})
}
