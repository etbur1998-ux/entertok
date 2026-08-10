package handlers

import (
	"log"
	"net/http"
	"strconv"

	"entertok-backend/models"
	"entertok-backend/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ProductHandler struct {
	DB *gorm.DB
}

func NewProductHandler(db *gorm.DB) *ProductHandler {
	return &ProductHandler{DB: db}
}

func (h *ProductHandler) GetProducts(c *gin.Context) {
	category := c.Query("category")
	search := c.Query("search")
	limit := c.DefaultQuery("limit", "20")
	offset := c.DefaultQuery("offset", "0")

	limitInt, _ := strconv.Atoi(limit)
	offsetInt, _ := strconv.Atoi(offset)

	query := h.DB.Model(&models.Product{}).Where("is_active = ?", true).Preload("Seller")

	if category != "" && category != "All" {
		query = query.Where("category = ?", category)
	}

	if search != "" {
		query = query.Where("name LIKE ? OR description LIKE ?", "%"+search+"%", "%"+search+"%")
	}

	var products []models.Product
	var total int64

	query.Count(&total)
	query.Order("created_at DESC").Limit(limitInt).Offset(offsetInt).Find(&products)

	c.JSON(http.StatusOK, gin.H{
		"products": products,
		"total":    total,
		"limit":    limitInt,
		"offset":   offsetInt,
	})
}

func (h *ProductHandler) GetProduct(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	var product models.Product
	if err := h.DB.Preload("Seller").First(&product, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	// Increment view count
	h.DB.Model(&product).Update("view_count", product.ViewCount+1)

	c.JSON(http.StatusOK, product)
}

func (h *ProductHandler) GetCategories(c *gin.Context) {
	categories := []string{"NFTs", "Gaming", "Music", "Art", "Virtual", "Fashion", "Collectibles"}
	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

func (h *ProductHandler) CreateProduct(c *gin.Context) {
	log.Println("=== CreateProduct handler called ===")
	userID := utils.GetCurrentUserID(c)
	log.Printf("User ID from context: %d", userID)

	var input struct {
		Name        string  `json:"name" binding:"required"`
		Description string  `json:"description"`
		Price       float64 `json:"price" binding:"required"`
		Currency    string  `json:"currency"`
		Category    string  `json:"category" binding:"required"`
		ImageURL    string  `json:"image_url"`
		MediaURL    string  `json:"media_url"`
		Stock       int     `json:"stock"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currency := input.Currency
	if currency == "" {
		currency = "USD"
	}

	stock := input.Stock
	if stock <= 0 {
		stock = 1
	}

	product := models.Product{
		SellerID:    userID,
		Name:        input.Name,
		Description: input.Description,
		Price:       input.Price,
		Currency:    currency,
		Category:    input.Category,
		ImageURL:    input.ImageURL,
		MediaURL:    input.MediaURL,
		Stock:       stock,
		IsActive:    true,
	}

	if err := h.DB.Create(&product).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create product"})
		return
	}

	h.DB.Preload("Seller").First(&product, product.ID)
	c.JSON(http.StatusCreated, product)
}

func (h *ProductHandler) UpdateProduct(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	if product.SellerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to update this product"})
		return
	}

	var input struct {
		Name        string  `json:"name"`
		Description string  `json:"description"`
		Price       float64 `json:"price"`
		Category    string  `json:"category"`
		ImageURL    string  `json:"image_url"`
		MediaURL    string  `json:"media_url"`
		Stock       int     `json:"stock"`
		IsActive    *bool   `json:"is_active"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := make(map[string]interface{})
	if input.Name != "" {
		updates["name"] = input.Name
	}
	if input.Description != "" {
		updates["description"] = input.Description
	}
	if input.Price > 0 {
		updates["price"] = input.Price
	}
	if input.Category != "" {
		updates["category"] = input.Category
	}
	if input.ImageURL != "" {
		updates["image_url"] = input.ImageURL
	}
	if input.MediaURL != "" {
		updates["media_url"] = input.MediaURL
	}
	if input.Stock > 0 {
		updates["stock"] = input.Stock
	}
	if input.IsActive != nil {
		updates["is_active"] = *input.IsActive
	}

	if err := h.DB.Model(&product).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update product"})
		return
	}

	h.DB.Preload("Seller").First(&product, product.ID)
	c.JSON(http.StatusOK, product)
}

func (h *ProductHandler) DeleteProduct(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	if product.SellerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to delete this product"})
		return
	}

	h.DB.Delete(&product)
	c.JSON(http.StatusOK, gin.H{"message": "Product deleted successfully"})
}

func (h *ProductHandler) LikeProduct(c *gin.Context) {
	userID := utils.GetCurrentUserID(c)
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		return
	}

	var existingLike models.ProductLike
	result := h.DB.Where("product_id = ? AND user_id = ?", id, userID).First(&existingLike)

	if result.Error == nil {
		h.DB.Delete(&existingLike)
		h.DB.Model(&product).Update("like_count", product.LikeCount-1)
		c.JSON(http.StatusOK, gin.H{"liked": false, "like_count": product.LikeCount - 1})
		return
	}

	like := models.ProductLike{
		ProductID: uint(id),
		UserID:    userID,
	}
	h.DB.Create(&like)
	h.DB.Model(&product).Update("like_count", product.LikeCount+1)

	c.JSON(http.StatusOK, gin.H{"liked": true, "like_count": product.LikeCount + 1})
}

func (h *ProductHandler) GetUserProducts(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var products []models.Product
	h.DB.Where("seller_id = ? AND is_active = ?", id, true).Preload("Seller").Order("created_at DESC").Find(&products)

	c.JSON(http.StatusOK, products)
}

func (h *ProductHandler) GetTrendingProducts(c *gin.Context) {
	var products []models.Product
	h.DB.Where("is_active = ?", true).Preload("Seller").Order("like_count DESC, view_count DESC").Limit(10).Find(&products)

	c.JSON(http.StatusOK, products)
}
