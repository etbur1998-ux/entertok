package main

import (
	"log"
	"os"
	"strconv"

	"entertok-backend/config"
	"entertok-backend/handlers"
	"entertok-backend/middleware"
	"entertok-backend/models"
	"entertok-backend/websocket"

	gzip "github.com/gin-contrib/gzip"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/joho/godotenv"
	"gorm.io/gorm"
)

func main() {
	// Load .env file
	if err := godotenv.Load("./.env"); err != nil {
		log.Printf("Warning: Failed to load .env file: %v", err)
	}
	log.Printf("JWT_SECRET from env: %s", os.Getenv("JWT_SECRET"))

	cfg := config.LoadConfig()
	db := config.ConnectDB(cfg)

	// Auto migrate database schema
	err := db.AutoMigrate(
		&models.User{},
		&models.Post{},
		&models.Comment{},
		&models.Like{},
		&models.CommentLike{},
		&models.Follow{},
		&models.Message{},
		&models.Conversation{},
		&models.GroupMember{},
		&models.Notification{},
		&models.SavedPost{},
		&models.Wallet{},
		&models.Transaction{},
		&models.Report{},
		&models.Product{},
		&models.ProductLike{},
		&models.LiveStream{},
		&models.LiveComment{},
		&models.Ad{},
		&models.Story{},
		&models.BoostCampaign{},
		&models.BoostReward{},
	)
	if err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}
	log.Println("Database migration completed!")

	// ── Performance indexes (run once, safe to re-run) ──────────────────────
	indexes := []string{
		// Feed query: posts by user_id + is_public
		"CREATE INDEX IF NOT EXISTS idx_posts_user_public ON posts(user_id, is_public)",
		// Like lookups: (user_id, post_id) batch fetch
		"CREATE INDEX IF NOT EXISTS idx_likes_user_post ON likes(user_id, post_id)",
		// Follow lookups: follower_id → following_id
		"CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id, following_id)",
		// Messages by conversation
		"CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at)",
		// Group messages
		"CREATE INDEX IF NOT EXISTS idx_messages_group ON messages(group_id, created_at)",
		// Notifications by user
		"CREATE INDEX IF NOT EXISTS idx_notifs_user ON notifications(user_id, created_at)",
	}
	for _, idx := range indexes {
		if err := db.Exec(idx).Error; err != nil {
			log.Printf("Index warning (safe to ignore): %v", err)
		}
	}
	log.Println("Performance indexes ensured.")

	// Initialize handlers
	authHandler := &handlers.AuthHandler{DB: db}
	userHandler := &handlers.UserHandler{DB: db}
	postHandler := &handlers.PostHandler{DB: db}
	messageHandler := &handlers.MessageHandler{DB: db}
	notificationHandler := &handlers.NotificationHandler{DB: db}
	commentHandler := &handlers.CommentHandler{DB: db}
	settingsHandler := &handlers.SettingsHandler{DB: db}
	uploadHandler := handlers.NewUploadHandler()
	groupHandler := handlers.NewGroupHandler(db)
	productHandler := handlers.NewProductHandler(db)
	liveHandler := handlers.NewLiveHandler(db)
	adHandler := handlers.NewAdHandler(db)
	storyHandler := handlers.NewStoryHandler(db)

	if err := handlers.InitUpload(); err != nil {
		log.Printf("Warning: Failed to initialize upload directory: %v", err)
	}

	seedSampleData(db)

	// Initialize WebSocket hub
	wsHub := websocket.NewHub(db)
	websocket.SetHub(wsHub)
	go wsHub.Run()

	// Setup Gin router
	router := gin.Default()
	router.MaxMultipartMemory = 100 << 20 // 100MB
	router.Use(middleware.CORSMiddleware())
	router.Use(gzip.Gzip(gzip.DefaultCompression)) // compress all JSON/text responses

	// ─── Health & Debug ───────────────────────────────────────────────────────
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":       "ok",
			"message":      "EnterTok API is running",
			"online_users": wsHub.GetOnlineCount(),
		})
	})

	router.GET("/debug/info", func(c *gin.Context) {
		var userCount, postCount, followCount int64
		db.Model(&models.User{}).Count(&userCount)
		db.Model(&models.Post{}).Count(&postCount)
		db.Model(&models.Follow{}).Count(&followCount)
		c.JSON(200, gin.H{
			"users":        userCount,
			"posts":        postCount,
			"follows":      followCount,
			"online_users": wsHub.GetOnlineCount(),
			"port":         os.Getenv("PORT"),
		})
	})

	router.GET("/debug/seed", func(c *gin.Context) {
		seedSampleData(db)
		c.JSON(200, gin.H{"message": "Data seeded"})
	})

	// Serve uploaded files
	router.Static("/uploads", "./uploads")

	// Serve Flutter web app (built with `flutter build web`)
	// Place the build/web folder next to the backend binary as "web_app"
	router.Static("/app", "./web_app")
	router.NoRoute(func(c *gin.Context) {
		// For any non-API, non-WS route → serve Flutter web index.html
		path := c.Request.URL.Path
		if len(path) > 4 && path[:5] == "/api/" {
			c.JSON(404, gin.H{"error": "Not found"})
			return
		}
		if path == "/ws" {
			c.JSON(404, gin.H{"error": "Not found"})
			return
		}
		c.File("./web_app/index.html")
	})

	// ─── WebSocket ────────────────────────────────────────────────────────────
	router.GET("/ws", func(c *gin.Context) {
		token := c.Query("token")
		if token == "" {
			c.JSON(401, gin.H{"error": "No token provided"})
			return
		}
		claims := &middleware.Claims{}
		tkn, err := jwt.ParseWithClaims(token, claims, func(token *jwt.Token) (interface{}, error) {
			return []byte(middleware.GetJWTSecret()), nil
		})
		if err != nil || !tkn.Valid {
			c.JSON(401, gin.H{"error": "Invalid token"})
			return
		}
		var user models.User
		if err := db.First(&user, claims.UserID).Error; err != nil {
			c.JSON(401, gin.H{"error": "User not found"})
			return
		}
		wsHub.HandleWebSocket(c.Writer, c.Request, &user)
	})

	// ─── API Routes ───────────────────────────────────────────────────────────
	api := router.Group("/api/v1")

	// Auth (public)
	auth := api.Group("/auth")
	{
		auth.POST("/register", authHandler.Register)
		auth.POST("/login", authHandler.Login)
		auth.POST("/google", authHandler.GoogleSignIn)
		auth.POST("/refresh", authHandler.RefreshToken)
	}
	// Auth (protected)
	authP := api.Group("/auth")
	authP.Use(middleware.AuthMiddleware())
	{
		authP.GET("/me", authHandler.GetCurrentUser)
		authP.POST("/change-password", authHandler.ChangePassword)
	}

	// Users
	users := api.Group("/users")
	{
		users.GET("/search", userHandler.SearchUsers)
		users.GET("/suggestions", userHandler.GetSuggestions)
		users.GET("/:id", userHandler.GetUser)
	}
	usersP := api.Group("/users")
	usersP.Use(middleware.AuthMiddleware())
	{
		usersP.PUT("/profile", userHandler.UpdateProfile)
		usersP.POST("/:id/follow", userHandler.FollowUser)
		usersP.DELETE("/:id/follow", userHandler.UnfollowUser)
		usersP.GET("/:id/followers", userHandler.GetFollowers)
		usersP.GET("/:id/following", userHandler.GetFollowing)
	}

	// Posts
	posts := api.Group("/posts")
	{
		posts.GET("/feed", postHandler.GetFeed)
		posts.GET("/trending", postHandler.GetTrending)
		posts.GET("/hashtags/trending", postHandler.GetTrendingHashtags)
		posts.GET("/user/:id", postHandler.GetUserPosts)
		posts.GET("/hashtag/:hashtag", postHandler.GetPostsByHashtag)
		posts.GET("/:id/comments", commentHandler.GetComments)
		posts.GET("/:id", postHandler.GetPost)
	}
	postsP := api.Group("/posts")
	postsP.Use(middleware.AuthMiddleware())
	{
		postsP.POST("", postHandler.CreatePost)
		postsP.DELETE("/:id", postHandler.DeletePost)
		postsP.POST("/:id/like", postHandler.LikePost)
		postsP.DELETE("/:id/like", postHandler.UnlikePost)
		postsP.POST("/:id/comments", commentHandler.CreateComment)
		postsP.DELETE("/comments/:commentId", commentHandler.DeleteComment)
		postsP.POST("/comments/:commentId/like", commentHandler.LikeComment)
		postsP.DELETE("/comments/:commentId/like", commentHandler.UnlikeComment)
	}

	// Messages (protected)
	messages := api.Group("/messages")
	messages.Use(middleware.AuthMiddleware())
	{
		messages.GET("/conversations", messageHandler.GetConversations)
		messages.GET("/conversations/:id/messages", messageHandler.GetMessages)
		messages.POST("", messageHandler.SendMessage)
		messages.GET("/unread", messageHandler.GetUnreadCount)
		messages.DELETE("/:id", messageHandler.DeleteMessage)
		messages.PUT("/:id", messageHandler.UpdateMessage)
	}

	// Groups (protected)
	groups := api.Group("/groups")
	groups.Use(middleware.AuthMiddleware())
	{
		groups.GET("", groupHandler.GetUserGroups)
		groups.POST("/create", groupHandler.CreateGroup)
		groups.GET("/:id", groupHandler.GetGroup)
		groups.PUT("/:id", groupHandler.UpdateGroup)
		groups.DELETE("/:id", groupHandler.LeaveGroup)
		groups.POST("/:id/members", groupHandler.AddMembers)
		groups.DELETE("/:id/members/:member_id", groupHandler.RemoveMember)
		groups.GET("/:id/members", groupHandler.GetGroupMembers)
		groups.GET("/:id/messages", groupHandler.GetGroupMessages)
		groups.POST("/:id/messages", groupHandler.SendGroupMessage)
	}

	// Notifications (protected)
	notifications := api.Group("/notifications")
	notifications.Use(middleware.AuthMiddleware())
	{
		notifications.GET("", notificationHandler.GetNotifications)
		notifications.GET("/unread", notificationHandler.GetUnreadCount)
		notifications.POST("/:id/read", notificationHandler.MarkAsRead)
		notifications.POST("/read-all", notificationHandler.MarkAllAsRead)
		notifications.DELETE("/:id", notificationHandler.Delete)
	}

	// Settings (protected)
	settings := api.Group("/settings")
	settings.Use(middleware.AuthMiddleware())
	{
		settings.GET("/notifications", settingsHandler.GetNotificationSettings)
		settings.PUT("/notifications", settingsHandler.UpdateNotificationSettings)
	}

	// Uploads (protected)
	uploads := api.Group("/uploads")
	uploads.Use(middleware.AuthMiddleware())
	{
		uploads.POST("/video", uploadHandler.UploadVideo)
		uploads.POST("/image", uploadHandler.UploadImage)
		uploads.POST("/file", uploadHandler.UploadFile)
	}

	// Products / Marketplace
	products := api.Group("/products")
	{
		products.GET("", productHandler.GetProducts)
		products.GET("/categories", productHandler.GetCategories)
		products.GET("/trending", productHandler.GetTrendingProducts)
		products.GET("/:id", productHandler.GetProduct)
		products.GET("/user/:id", productHandler.GetUserProducts)
	}
	productsP := api.Group("/products")
	productsP.Use(middleware.AuthMiddleware())
	{
		productsP.POST("", productHandler.CreateProduct)
		productsP.PUT("/:id", productHandler.UpdateProduct)
		productsP.DELETE("/:id", productHandler.DeleteProduct)
		productsP.POST("/:id/like", productHandler.LikeProduct)
	}

	// Live Streams
	live := api.Group("/live")
	{
		live.GET("", liveHandler.GetActiveLives)
		live.GET("/:id", liveHandler.GetLiveStream)
		live.GET("/:id/comments", liveHandler.GetLiveComments)
	}
	liveP := api.Group("/live")
	liveP.Use(middleware.AuthMiddleware())
	{
		liveP.POST("/start", liveHandler.StartLive)
		liveP.POST("/:id/end", liveHandler.EndLive)
		liveP.POST("/:id/gift", liveHandler.SendLiveGift)
	}

	// Stories
	stories := api.Group("/stories")
	{
		stories.GET("/user/:id", storyHandler.GetUserStories)
	}
	storiesP := api.Group("/stories")
	storiesP.Use(middleware.AuthMiddleware())
	{
		storiesP.GET("", storyHandler.GetStories)
		storiesP.POST("", storyHandler.CreateStory)
		storiesP.POST("/:id/view", storyHandler.ViewStory)
		storiesP.DELETE("/:id", storyHandler.DeleteStory)
	}

	// Dating
	datingHandler := handlers.NewDatingHandler(db)
	dating := api.Group("/dating")
	dating.Use(middleware.AuthMiddleware())
	dating.GET("/suggestions", datingHandler.GetSuggestions)
	dating.GET("/likes", datingHandler.GetLikes)
	dating.GET("/matches", datingHandler.GetMatches)
	dating.POST("/like/:id", datingHandler.LikeUser)
	dating.POST("/dislike/:id", datingHandler.DislikeUser)

	// Boost / Paid Followers
	boostHandler := handlers.NewBoostHandler(db)
	boost := api.Group("/boost")
	boost.GET("/active", boostHandler.GetActiveBoostedUsers)
	boostP := api.Group("/boost")
	boostP.Use(middleware.AuthMiddleware())
	{
		boostP.POST("",              boostHandler.CreateBoost)
		boostP.GET("/my",            boostHandler.GetMyBoosts)
		boostP.GET("/stats",         boostHandler.GetBoostStats)
		boostP.POST("/:id/pause",    boostHandler.PauseBoost)
		boostP.POST("/:id/cancel",   boostHandler.CancelBoost)
	}

	// Admin routes (protected)
	adminHandler := handlers.NewAdminHandler(db)
	adminRoutes := api.Group("/admin")
	adminRoutes.Use(middleware.AuthMiddleware())
	{
		adminRoutes.GET("/users",                   adminHandler.GetAllUsers)
		adminRoutes.GET("/posts",                   adminHandler.GetAllPosts)
		adminRoutes.DELETE("/posts/:id",            adminHandler.DeleteUserPost)
		adminRoutes.POST("/users/:id/ban",          adminHandler.BanUser)
		adminRoutes.POST("/users/:id/unban",        adminHandler.UnbanUser)
		adminRoutes.POST("/users/:id/verify",       adminHandler.VerifyUser)
		adminRoutes.GET("/ads",                     adminHandler.GetAllAds)
		adminRoutes.GET("/stats",                   adminHandler.GetStats)
		adminRoutes.GET("/conversations",           adminHandler.GetAllConversations)
		adminRoutes.GET("/conversations/:id/messages", adminHandler.GetConversationMessages)
		adminRoutes.DELETE("/messages/:id",         adminHandler.AdminDeleteMessage)
		adminRoutes.POST("/messages/send",          adminHandler.SendMessageAsAdmin)
		// Boost admin routes
		adminRoutes.GET("/boosts",                  boostHandler.AdminGetAllBoosts)
		adminRoutes.GET("/boosts/rewards",          boostHandler.AdminGetBoostRewards)
		adminRoutes.POST("/boosts/:id/stop",        boostHandler.AdminForceStopBoost)
	}

	// Wallet
	walletHandler := handlers.NewWalletHandler(db)
	walletRoutes := api.Group("/wallet")
	walletRoutes.Use(middleware.AuthMiddleware())
	{
		walletRoutes.GET("", walletHandler.GetWallet)
		walletRoutes.GET("/transactions", walletHandler.GetTransactions)
		walletRoutes.GET("/stats", walletHandler.GetWalletStats)
		walletRoutes.POST("/topup", walletHandler.TopUp)
		walletRoutes.POST("/send", walletHandler.SendMoney)
		walletRoutes.POST("/withdraw", walletHandler.Withdraw)
	}

	// Ads / Marketing
	ads := api.Group("/ads")
	ads.GET("/feed", adHandler.GetFeedAds)
	ads.POST("/:id/impression", adHandler.TrackAdImpression)
	ads.POST("/:id/click", adHandler.TrackAdClick)

	adsP := api.Group("/ads")
	adsP.Use(middleware.AuthMiddleware())
	adsP.POST("", adHandler.CreateAd)
	adsP.GET("/my", adHandler.GetMyAds)
	adsP.PUT("/:id", adHandler.UpdateAd)
	adsP.DELETE("/:id", adHandler.DeleteAd)
	adsP.GET("/:id/stats", adHandler.GetAdStats)

	// Video proxy
	router.GET("/api/v1/proxy/video", uploadHandler.ProxyVideo)

	// Debug routes
	router.GET("/debug/routes", func(c *gin.Context) {
		routes := router.Routes()
		var routeList []string
		for _, r := range routes {
			routeList = append(routeList, r.Method+" "+r.Path)
		}
		c.JSON(200, gin.H{"routes": routeList})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 EnterTok server starting on port %s...", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func strToInt(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func seedSampleData(db interface{}) {
	gormDB := db.(*gorm.DB)

	var firstUser models.User
	gormDB.First(&firstUser)
	if firstUser.ID == 0 {
		log.Println("No users found, skipping seed")
		return
	}

	// Seed sample users
	var existingCount int64
	gormDB.Model(&models.User{}).Count(&existingCount)
	if existingCount < 15 {
		sampleUsers := []models.User{
			{Username: "alice", FullName: "Alice Smith", Email: "alice@example.com", Bio: "Hey there! I'm Alice."},
			{Username: "bob", FullName: "Bob Johnson", Email: "bob@example.com", Bio: "Tech enthusiast 🚀"},
			{Username: "charlie", FullName: "Charlie Brown", Email: "charlie@example.com", Bio: "Music lover 🎵"},
			{Username: "diana", FullName: "Diana Prince", Email: "diana@example.com", Bio: "Travel the world ✈️"},
			{Username: "emma", FullName: "Emma Wilson", Email: "emma@example.com", Bio: "Foodie 🍕"},
			{Username: "frank", FullName: "Frank Miller", Email: "frank@example.com", Bio: "Photography 📸"},
			{Username: "grace", FullName: "Grace Lee", Email: "grace@example.com", Bio: "Fitness coach 💪"},
			{Username: "henry", FullName: "Henry Ford", Email: "henry@example.com", Bio: "Car enthusiast 🚗"},
			{Username: "iris", FullName: "Iris Wang", Email: "iris@example.com", Bio: "Art student 🎨"},
			{Username: "jack", FullName: "Jack Davis", Email: "jack@example.com", Bio: "Gamer 🎮"},
		}
		for i := range sampleUsers {
			var check models.User
			if gormDB.Where("username = ?", sampleUsers[i].Username).First(&check).RowsAffected == 0 {
				sampleUsers[i].Password = "dummy"
				gormDB.Create(&sampleUsers[i])
				log.Printf("Created sample user: %s", sampleUsers[i].Username)
			}
		}
	}

	// Seed posts
	sampleVideos := []struct {
		Content   string
		MediaURL  string
	}{
		{"Check out this amazing video! #viral #trending", "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4"},
		{"Awesome content coming your way! 🎉", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"},
		{"Look at this! #fyp #viral", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4"},
		{"Amazing nature clip 🌿 #nature #wildlife", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"},
		{"Check this out! #cool #awesome", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4"},
		{"Incredible footage! 🔥 #viral #trending", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"},
		{"Must watch! ⭐ #viral #fyp", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"},
		{"You need to see this! 🚀 #trending", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4"},
		{"Wow! Just wow! 😍 #viral #amazing", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"},
	}

	var count int64
	gormDB.Model(&models.Post{}).Count(&count)
	if count < int64(len(sampleVideos)) {
		for _, v := range sampleVideos {
			post := models.Post{
				UserID:    firstUser.ID,
				Content:   v.Content,
				MediaURL:  v.MediaURL,
				MediaType: "video",
				IsPublic:  true,
			}
			gormDB.Create(&post)
		}
		log.Printf("Seeded %d sample posts", len(sampleVideos))
	}

	// Seed products
	var productCount int64
	gormDB.Model(&models.Product{}).Count(&productCount)
	if productCount == 0 {
		sampleProducts := []models.Product{
			{Name: "Premium NFT #001", Description: "Exclusive digital collectible", Price: 0.5, Currency: "ETH", Category: "NFTs", ImageURL: "https://picsum.photos/400/400?random=1", Stock: 1, Rating: 4.8, LikeCount: 234, SellerID: firstUser.ID},
			{Name: "Gaming Skin Pack", Description: "Ultimate gaming skins bundle", Price: 25.0, Currency: "USD", Category: "Gaming", ImageURL: "https://picsum.photos/400/400?random=2", Stock: 100, Rating: 4.5, LikeCount: 156, SellerID: firstUser.ID},
			{Name: "Virtual Land Plot", Description: "Prime virtual real estate in metaverse", Price: 2.0, Currency: "ETH", Category: "Virtual", ImageURL: "https://picsum.photos/400/400?random=3", Stock: 1, Rating: 4.9, LikeCount: 89, SellerID: firstUser.ID},
			{Name: "Music Token VIP", Description: "Exclusive VIP token for music events", Price: 10.0, Currency: "USD", Category: "Music", ImageURL: "https://picsum.photos/400/400?random=4", Stock: 500, Rating: 4.3, LikeCount: 312, SellerID: firstUser.ID},
			{Name: "Art Collection Set", Description: "Beautiful digital art collection", Price: 1.5, Currency: "ETH", Category: "Art", ImageURL: "https://picsum.photos/400/400?random=5", Stock: 10, Rating: 4.7, LikeCount: 178, SellerID: firstUser.ID},
			{Name: "Avatar Premium Pack", Description: "Premium avatar customization pack", Price: 50.0, Currency: "USD", Category: "Gaming", ImageURL: "https://picsum.photos/400/400?random=6", Stock: 50, Rating: 4.6, LikeCount: 267, SellerID: firstUser.ID},
			{Name: "NFT Mystery Box", Description: "Mystery box with rare NFTs", Price: 0.3, Currency: "ETH", Category: "NFTs", ImageURL: "https://picsum.photos/400/400?random=7", Stock: 200, Rating: 4.4, LikeCount: 445, SellerID: firstUser.ID},
			{Name: "Concert Ticket NFT", Description: "Exclusive concert ticket as NFT", Price: 5.0, Currency: "USD", Category: "Music", ImageURL: "https://picsum.photos/400/400?random=10", Stock: 300, Rating: 4.9, LikeCount: 567, SellerID: firstUser.ID},
		}
		for _, p := range sampleProducts {
			gormDB.Create(&p)
		}
		log.Printf("Seeded %d sample products", len(sampleProducts))
	}
}
