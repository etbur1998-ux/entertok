package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type WalletHandler struct {
	DB *gorm.DB
}

func NewWalletHandler(db *gorm.DB) *WalletHandler {
	return &WalletHandler{DB: db}
}

func generateWalletAddress() string {
	b := make([]byte, 8)
	rand.Read(b)
	return "ETBP" + hex.EncodeToString(b)
}

// GetWallet returns the user's wallet + balance
func (h *WalletHandler) GetWallet(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var wallet models.Wallet
	result := h.DB.Where("user_id = ?", userID).First(&wallet)

	if result.Error == gorm.ErrRecordNotFound {
		// Auto-create wallet
		wallet = models.Wallet{
			UserID:        userID,
			Balance:       0,
			Currency:      "USD",
			WalletAddress: generateWalletAddress(),
			IsActive:      true,
		}
		h.DB.Create(&wallet)
	} else if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get wallet"})
		return
	}

	// Generate address if missing
	if wallet.WalletAddress == "" {
		wallet.WalletAddress = generateWalletAddress()
		h.DB.Save(&wallet)
	}

	c.JSON(http.StatusOK, gin.H{
		"id":             wallet.ID,
		"balance":        wallet.Balance,
		"currency":       wallet.Currency,
		"wallet_address": wallet.WalletAddress,
		"is_active":      wallet.IsActive,
		"created_at":     wallet.CreatedAt,
	})
}

// GetTransactions returns transaction history for the user
func (h *WalletHandler) GetTransactions(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	txType := c.Query("type") // deposit, withdrawal, transfer, tip

	var wallet models.Wallet
	if err := h.DB.Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"transactions": []interface{}{}, "total": 0})
		return
	}

	query := h.DB.Where("wallet_id = ?", wallet.ID)
	if txType != "" {
		query = query.Where("type = ?", txType)
	}

	var total int64
	query.Model(&models.Transaction{}).Count(&total)

	var txs []models.Transaction
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&txs)

	var results []gin.H
	for _, tx := range txs {
		results = append(results, gin.H{
			"id":           tx.ID,
			"type":         tx.Type,
			"amount":       tx.Amount,
			"fee":          tx.Fee,
			"description":  tx.Description,
			"reference_id": tx.ReferenceID,
			"status":       tx.Status,
			"created_at":   tx.CreatedAt,
		})
	}

	if results == nil {
		results = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"transactions": results,
		"total":        total,
		"page":         page,
		"page_size":    pageSize,
	})
}

// TopUp adds funds to wallet (simulated)
func (h *WalletHandler) TopUp(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		Amount      float64 `json:"amount" binding:"required"`
		Method      string  `json:"method"` // card, bank, crypto
		Description string  `json:"description"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Amount must be positive"})
		return
	}

	var wallet models.Wallet
	if err := h.DB.Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wallet not found"})
		return
	}

	// Add balance
	newBalance := wallet.Balance + input.Amount
	h.DB.Model(&wallet).Update("balance", newBalance)

	// Create transaction record
	desc := input.Description
	if desc == "" {
		desc = fmt.Sprintf("Top-up via %s", input.Method)
	}
	tx := models.Transaction{
		WalletID:    wallet.ID,
		Type:        "deposit",
		Amount:      input.Amount,
		Fee:         0,
		Description: desc,
		ReferenceID: generateTxRef(),
		Status:      "completed",
	}
	h.DB.Create(&tx)

	c.JSON(http.StatusOK, gin.H{
		"message":     "Funds added successfully",
		"new_balance": newBalance,
		"transaction": gin.H{
			"id":     tx.ID,
			"type":   tx.Type,
			"amount": tx.Amount,
			"status": tx.Status,
		},
	})
}

// SendMoney transfers funds to another user by wallet address
func (h *WalletHandler) SendMoney(c *gin.Context) {
	senderID := utils.GetCurrentUserID(c)

	var input struct {
		RecipientAddress string  `json:"recipient_address" binding:"required"`
		Amount           float64 `json:"amount" binding:"required"`
		Description      string  `json:"description"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Amount must be positive"})
		return
	}

	// Get sender wallet
	var senderWallet models.Wallet
	if err := h.DB.Where("user_id = ?", senderID).First(&senderWallet).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Your wallet not found"})
		return
	}

	fee := input.Amount * 0.01 // 1% fee
	totalDeducted := input.Amount + fee

	if senderWallet.Balance < totalDeducted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient balance"})
		return
	}

	// Find recipient wallet
	var recipientWallet models.Wallet
	if err := h.DB.Where("wallet_address = ?", input.RecipientAddress).
		First(&recipientWallet).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Recipient wallet not found"})
		return
	}

	if recipientWallet.UserID == senderID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot send to your own wallet"})
		return
	}

	refID := generateTxRef()
	now := time.Now()

	// Deduct from sender
	h.DB.Model(&senderWallet).Update("balance", senderWallet.Balance-totalDeducted)
	h.DB.Create(&models.Transaction{
		WalletID:    senderWallet.ID,
		Type:        "transfer",
		Amount:      -input.Amount,
		Fee:         fee,
		Description: fmt.Sprintf("Sent to %s. %s", input.RecipientAddress, input.Description),
		ReferenceID: refID,
		Status:      "completed",
		CreatedAt:   now,
	})

	// Add to recipient
	h.DB.Model(&recipientWallet).Update("balance", recipientWallet.Balance+input.Amount)
	h.DB.Create(&models.Transaction{
		WalletID:    recipientWallet.ID,
		Type:        "transfer",
		Amount:      input.Amount,
		Fee:         0,
		Description: fmt.Sprintf("Received from user #%d. %s", senderID, input.Description),
		ReferenceID: refID,
		Status:      "completed",
		CreatedAt:   now,
	})

	// Get recipient user info
	var recipientUser models.User
	h.DB.First(&recipientUser, recipientWallet.UserID)

	c.JSON(http.StatusOK, gin.H{
		"message":         "Transfer successful",
		"amount_sent":     input.Amount,
		"fee":             fee,
		"total_deducted":  totalDeducted,
		"new_balance":     senderWallet.Balance - totalDeducted,
		"recipient":       recipientUser.Username,
		"reference":       refID,
	})
}

// Withdraw requests a withdrawal
func (h *WalletHandler) Withdraw(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var input struct {
		Amount      float64 `json:"amount" binding:"required"`
		Method      string  `json:"method"` // bank, paypal, crypto
		Destination string  `json:"destination"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Amount must be positive"})
		return
	}

	var wallet models.Wallet
	if err := h.DB.Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wallet not found"})
		return
	}

	fee := input.Amount * 0.02 // 2% withdrawal fee
	totalDeducted := input.Amount + fee

	if wallet.Balance < totalDeducted {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient balance"})
		return
	}

	h.DB.Model(&wallet).Update("balance", wallet.Balance-totalDeducted)

	tx := models.Transaction{
		WalletID:    wallet.ID,
		Type:        "withdrawal",
		Amount:      -input.Amount,
		Fee:         fee,
		Description: fmt.Sprintf("Withdrawal via %s to %s", input.Method, input.Destination),
		ReferenceID: generateTxRef(),
		Status:      "pending", // withdrawals require processing
	}
	h.DB.Create(&tx)

	c.JSON(http.StatusOK, gin.H{
		"message":     "Withdrawal request submitted",
		"amount":      input.Amount,
		"fee":         fee,
		"new_balance": wallet.Balance - totalDeducted,
		"status":      "pending",
		"note":        "Withdrawal will be processed within 1-3 business days",
	})
}

// GetWalletStats returns summary stats
func (h *WalletHandler) GetWalletStats(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)

	var wallet models.Wallet
	if err := h.DB.Where("user_id = ?", userID).First(&wallet).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"total_sent": 0, "total_received": 0, "total_fees": 0})
		return
	}

	var totalReceived, totalSent, totalFees float64
	h.DB.Model(&models.Transaction{}).
		Where("wallet_id = ? AND amount > 0 AND type IN ('deposit','transfer')", wallet.ID).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalReceived)
	h.DB.Model(&models.Transaction{}).
		Where("wallet_id = ? AND amount < 0", wallet.ID).
		Select("COALESCE(SUM(ABS(amount)), 0)").Scan(&totalSent)
	h.DB.Model(&models.Transaction{}).
		Where("wallet_id = ?", wallet.ID).
		Select("COALESCE(SUM(fee), 0)").Scan(&totalFees)

	c.JSON(http.StatusOK, gin.H{
		"balance":        wallet.Balance,
		"total_received": totalReceived,
		"total_sent":     totalSent,
		"total_fees":     totalFees,
		"currency":       wallet.Currency,
		"wallet_address": wallet.WalletAddress,
	})
}

func generateTxRef() string {
	b := make([]byte, 8)
	rand.Read(b)
	return fmt.Sprintf("TX%s%d", hex.EncodeToString(b)[:8], time.Now().Unix()%10000)
}
