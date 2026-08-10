package models

import (
	"time"

	"gorm.io/gorm"
)

// User represents a user in the system
type User struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	Username       string         `gorm:"uniqueIndex;size:50;not null" json:"username"`
	Email          string         `gorm:"uniqueIndex;size:100;not null" json:"email"`
	Password       string         `gorm:"not null" json:"-"`
	FullName       string         `gorm:"size:100" json:"full_name"`
	Bio            string         `gorm:"type:text" json:"bio"`
	ProfileImage   string         `gorm:"size:255" json:"profile_image"`
	CoverImage     string         `gorm:"size:255" json:"cover_image"`
	Phone          string         `gorm:"size:20" json:"phone"`
	Website        string         `gorm:"size:255" json:"website"`
	Location       string         `gorm:"size:100" json:"location"`
	BirthDate      *time.Time     `json:"birth_date"`
	Gender         string         `gorm:"size:20" json:"gender"`
	IsVerified     bool           `gorm:"default:false" json:"is_verified"`
	IsPrivate      bool           `gorm:"default:false" json:"is_private"`
	IsOnline       bool           `gorm:"default:false" json:"is_online"`
	LastSeenAt     *time.Time     `json:"last_seen_at"`
	Role           string         `gorm:"size:20;default:user" json:"role"`
	PostCount      int            `gorm:"default:0" json:"post_count"`
	FollowerCount  int            `gorm:"default:0" json:"follower_count"`
	FollowingCount int            `gorm:"default:0" json:"following_count"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Posts         []Post         `gorm:"foreignKey:UserID" json:"posts,omitempty"`
	Followers     []Follow       `gorm:"foreignKey:FollowingID" json:"followers,omitempty"`
	Following     []Follow       `gorm:"foreignKey:FollowerID" json:"following,omitempty"`
	Notifications []Notification `gorm:"foreignKey:UserID" json:"notifications,omitempty"`
}

// Post represents a post/video in the system
type Post struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	Content        string         `gorm:"type:text" json:"content"`
	MediaURL       string         `gorm:"size:255" json:"media_url"`
	MediaType      string         `gorm:"size:20" json:"media_type"` // video, image
	Thumbnail      string         `gorm:"size:255" json:"thumbnail"`
	Duration       int            `gorm:"default:0" json:"duration"` // in seconds
	Location       string         `gorm:"size:100" json:"location"`
	HashTags       string         `gorm:"size:500" json:"hash_tags"` // comma-separated
	MentionedUsers string         `gorm:"size:500" json:"mentioned_users"`
	ViewCount      int            `gorm:"default:0" json:"view_count"`
	LikeCount      int            `gorm:"default:0" json:"like_count"`
	CommentCount   int            `gorm:"default:0" json:"comment_count"`
	ShareCount     int            `gorm:"default:0" json:"share_count"`
	SaveCount      int            `gorm:"default:0" json:"save_count"`
	IsPublic       bool           `gorm:"default:true" json:"is_public"`
	AllowComments  bool           `gorm:"default:true" json:"allow_comments"`
	AllowDuet      bool           `gorm:"default:true" json:"allow_duet"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User     User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Comments []Comment `gorm:"foreignKey:PostID" json:"comments,omitempty"`
	Likes    []Like    `gorm:"foreignKey:PostID" json:"likes,omitempty"`
}

// Comment represents a comment on a post
type Comment struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	PostID    uint           `gorm:"not null;index" json:"post_id"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	ParentID  *uint          `gorm:"index" json:"parent_id"`
	Content   string         `gorm:"type:text;not null" json:"content"`
	LikeCount int            `gorm:"default:0" json:"like_count"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Post    Post          `gorm:"foreignKey:PostID" json:"post,omitempty"`
	User    User          `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Parent  *Comment      `gorm:"foreignKey:ParentID" json:"parent,omitempty"`
	Replies []Comment     `gorm:"foreignKey:ParentID" json:"replies,omitempty"`
	Likes   []CommentLike `gorm:"foreignKey:CommentID" json:"likes,omitempty"`
}

// Like represents a like on a post
type Like struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	PostID    uint      `gorm:"not null;index" json:"post_id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`

	// Relationships
	Post Post `gorm:"foreignKey:PostID" json:"post,omitempty"`
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// CommentLike represents a like on a comment
type CommentLike struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	CommentID uint      `gorm:"not null;index" json:"comment_id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

// Follow represents a follow relationship between users
type Follow struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	FollowerID  uint      `gorm:"not null;index" json:"follower_id"`
	FollowingID uint      `gorm:"not null;index" json:"following_id"`
	CreatedAt   time.Time `json:"created_at"`

	// Relationships
	Follower  User `gorm:"foreignKey:FollowerID" json:"follower,omitempty"`
	Following User `gorm:"foreignKey:FollowingID" json:"following,omitempty"`
}

// Message represents a direct message
type Message struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	SenderID       uint           `gorm:"not null;index" json:"sender_id"`
	ReceiverID     uint           `gorm:"not null;index" json:"receiver_id"`
	Content        string         `gorm:"type:text;not null" json:"content"`
	MediaURL       string         `gorm:"size:255" json:"media_url"`
	MediaType      string         `gorm:"size:20" json:"media_type"`
	IsRead         bool           `gorm:"default:false" json:"is_read"`
	IsDelivered    bool           `gorm:"default:false" json:"is_delivered"`
	IsEdited       bool           `gorm:"default:false" json:"is_edited"`
	ReplyToID      *uint          `gorm:"index" json:"reply_to_id"`
	ConversationID uint           `gorm:"index" json:"conversation_id"`
	IsGroup        bool           `gorm:"default:false" json:"is_group"`
	GroupID        uint           `gorm:"index" json:"group_id"`
	Reactions      string         `gorm:"size:500" json:"reactions"` // JSON string of reactions
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Sender   User     `gorm:"foreignKey:SenderID" json:"sender,omitempty"`
	Receiver User     `gorm:"foreignKey:ReceiverID" json:"receiver,omitempty"`
	ReplyTo  *Message `gorm:"foreignKey:ReplyToID" json:"reply_to,omitempty"`
}

// Conversation represents a chat conversation
type Conversation struct {
	ID            uint           `gorm:"primaryKey" json:"id"`
	IsGroup       bool           `gorm:"default:false" json:"is_group"`
	GroupName     string         `gorm:"size:100" json:"group_name"`
	GroupAvatar   string         `gorm:"size:255" json:"group_avatar"`
	GroupDesc     string         `gorm:"type:text" json:"group_desc"`
	Participant1  uint           `gorm:"not null;index" json:"participant1"`
	Participant2  uint           `gorm:"not null;index" json:"participant2"`
	LastMessageID *uint          `json:"last_message_id"`
	LastMessageAt *time.Time     `json:"last_message_at"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Members []GroupMember `gorm:"foreignKey:ConversationID" json:"members,omitempty"`
}

// GroupMember represents a member of a group conversation
type GroupMember struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	ConversationID uint           `gorm:"not null;index" json:"conversation_id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	Role           string         `gorm:"size:20;default:member" json:"role"` // admin, member, moderator
	JoinedAt       time.Time      `json:"joined_at"`
	LastReadAt     *time.Time     `json:"last_read_at"`
	IsMuted        bool           `gorm:"default:false" json:"is_muted"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User         User         `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Conversation Conversation `gorm:"foreignKey:ConversationID" json:"-"`
}

// Notification represents a user notification
type Notification struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	Type      string         `gorm:"size:50;not null" json:"type"` // like, comment, follow, message, mention
	ActorID   uint           `gorm:"not null" json:"actor_id"`
	PostID    *uint          `gorm:"index" json:"post_id"`
	CommentID *uint          `gorm:"index" json:"comment_id"`
	Message   string         `gorm:"type:text" json:"message"`
	IsRead    bool           `gorm:"default:false" json:"is_read"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User  User  `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Actor User  `gorm:"foreignKey:ActorID" json:"actor,omitempty"`
	Post  *Post `gorm:"foreignKey:PostID" json:"post,omitempty"`
}

// SavedPost represents a saved post by a user
type SavedPost struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	PostID    uint      `gorm:"not null;index" json:"post_id"`
	CreatedAt time.Time `json:"created_at"`

	// Relationships
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Post Post `gorm:"foreignKey:PostID" json:"post,omitempty"`
}

// Wallet represents a user's wallet
type Wallet struct {
	ID            uint           `gorm:"primaryKey" json:"id"`
	UserID        uint           `gorm:"uniqueIndex;not null" json:"user_id"`
	Balance       float64        `gorm:"default:0.00" json:"balance"`
	Currency      string         `gorm:"size:10;default:USD" json:"currency"`
	WalletAddress string         `gorm:"size:100" json:"wallet_address"`
	IsActive      bool           `gorm:"default:true" json:"is_active"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// Transaction represents a wallet transaction
type Transaction struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	WalletID    uint           `gorm:"not null;index" json:"wallet_id"`
	Type        string         `gorm:"size:20;not null" json:"type"` // deposit, withdrawal, transfer, tip
	Amount      float64        `gorm:"not null" json:"amount"`
	Fee         float64        `gorm:"default:0" json:"fee"`
	Description string         `gorm:"size:255" json:"description"`
	ReferenceID string         `gorm:"size:100" json:"reference_id"`
	Status      string         `gorm:"size:20;default:pending" json:"status"` // pending, completed, failed
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Wallet Wallet `gorm:"foreignKey:WalletID" json:"wallet,omitempty"`
}

// Report represents a content report
type Report struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	ReporterID     uint           `gorm:"not null;index" json:"reporter_id"`
	ReportedUserID *uint          `gorm:"index" json:"reported_user_id"`
	PostID         *uint          `gorm:"index" json:"post_id"`
	Reason         string         `gorm:"size:50;not null" json:"reason"`
	Description    string         `gorm:"type:text" json:"description"`
	Status         string         `gorm:"size:20;default:pending" json:"status"` // pending, reviewed, resolved
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Reporter     User  `gorm:"foreignKey:ReporterID" json:"reporter,omitempty"`
	ReportedUser *User `gorm:"foreignKey:ReportedUserID" json:"reported_user,omitempty"`
	Post         *Post `gorm:"foreignKey:PostID" json:"post,omitempty"`
}

// Product represents a marketplace product
type Product struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	SellerID    uint           `gorm:"not null;index" json:"seller_id"`
	Name        string         `gorm:"size:255;not null" json:"name"`
	Description string         `gorm:"type:text" json:"description"`
	Price       float64        `gorm:"not null" json:"price"`
	Currency    string         `gorm:"size:10;default:USD" json:"currency"` // USD, ETH, USDT
	Category    string         `gorm:"size:50" json:"category"`             // NFTs, Gaming, Music, Art, Virtual
	ImageURL    string         `gorm:"size:255" json:"image_url"`
	MediaURL    string         `gorm:"size:255" json:"media_url"`
	Stock       int            `gorm:"default:1" json:"stock"`
	SoldCount   int            `gorm:"default:0" json:"sold_count"`
	ViewCount   int            `gorm:"default:0" json:"view_count"`
	LikeCount   int            `gorm:"default:0" json:"like_count"`
	Rating      float64        `gorm:"default:0" json:"rating"`
	IsActive    bool           `gorm:"default:true" json:"is_active"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Seller User `gorm:"foreignKey:SellerID" json:"seller,omitempty"`
}

// ProductLike represents a like on a product
type ProductLike struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	ProductID uint      `gorm:"not null;index" json:"product_id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`

	// Relationships
	Product Product `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	User    User    `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// LiveStream represents a live streaming session
type LiveStream struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	UserID       uint           `gorm:"not null;index" json:"user_id"`
	Title        string         `gorm:"size:255" json:"title"`
	Description  string         `gorm:"type:text" json:"description"`
	StreamKey    string         `gorm:"size:100;uniqueIndex" json:"stream_key"`
	ThumbnailURL string         `gorm:"size:255" json:"thumbnail_url"`
	ViewerCount  int            `gorm:"default:0" json:"viewer_count"`
	LikeCount    int            `gorm:"default:0" json:"like_count"`
	IsActive     bool           `gorm:"default:true" json:"is_active"`
	StartedAt    time.Time      `json:"started_at"`
	EndedAt      *time.Time     `json:"ended_at"`
	CreatedAt    time.Time      `json:"created_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// LiveComment represents a comment during a live stream
type LiveComment struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	StreamID   uint      `gorm:"not null;index" json:"stream_id"`
	UserID     uint      `gorm:"not null;index" json:"user_id"`
	Content    string    `gorm:"type:text;not null" json:"content"`
	CommentType string   `gorm:"size:20;default:text" json:"comment_type"` // text, gift, join
	GiftValue  float64   `gorm:"default:0" json:"gift_value"`
	CreatedAt  time.Time `json:"created_at"`

	// Relationships
	User   User       `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Stream LiveStream `gorm:"foreignKey:StreamID" json:"stream,omitempty"`
}

// Ad represents a marketing advertisement
type Ad struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	AdvertiserID uint           `gorm:"not null;index" json:"advertiser_id"`
	Title        string         `gorm:"size:255;not null" json:"title"`
	Description  string         `gorm:"type:text" json:"description"`
	MediaURL     string         `gorm:"size:255" json:"media_url"`
	MediaType    string         `gorm:"size:20" json:"media_type"` // video, image, banner
	TargetURL    string         `gorm:"size:255" json:"target_url"`
	Budget       float64        `gorm:"default:0" json:"budget"`
	SpentAmount  float64        `gorm:"default:0" json:"spent_amount"`
	ImpressionCount int         `gorm:"default:0" json:"impression_count"`
	ClickCount   int            `gorm:"default:0" json:"click_count"`
	Status       string         `gorm:"size:20;default:active" json:"status"` // active, paused, completed
	StartDate    time.Time      `json:"start_date"`
	EndDate      *time.Time     `json:"end_date"`
	TargetAge    string         `gorm:"size:50" json:"target_age"`
	TargetGender string         `gorm:"size:20" json:"target_gender"`
	TargetInterests string      `gorm:"size:500" json:"target_interests"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Advertiser User `gorm:"foreignKey:AdvertiserID" json:"advertiser,omitempty"`
}

// BoostCampaign represents a paid follower boost campaign
// Buyer pays 2.00 Birr per follower.
// When a new follower follows the boosted user → follower earns 1.70 Birr, platform earns 0.30 Birr.
type BoostCampaign struct {
	ID              uint           `gorm:"primaryKey" json:"id"`
	UserID          uint           `gorm:"not null;index" json:"user_id"`      // who is boosting
	TargetFollowers int            `gorm:"not null" json:"target_followers"`   // how many followers to buy
	PricePerFollower float64       `gorm:"default:2.00" json:"price_per_follower"` // 2 Birr
	EarnPerFollower  float64       `gorm:"default:1.70" json:"earn_per_follower"`  // follower earns 1.70
	FeePerFollower   float64       `gorm:"default:0.30" json:"fee_per_follower"`   // platform keeps 0.30
	TotalCost       float64        `gorm:"not null" json:"total_cost"`         // target * 2.00
	TotalSpent      float64        `gorm:"default:0" json:"total_spent"`       // actual spent so far
	FollowersGained int            `gorm:"default:0" json:"followers_gained"`  // actual follows received
	Status          string         `gorm:"size:20;default:active" json:"status"` // active, completed, paused, cancelled
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

// BoostReward represents a payment made to a follower for following a boosted user
type BoostReward struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	CampaignID   uint           `gorm:"not null;index" json:"campaign_id"`
	FollowerID   uint           `gorm:"not null;index" json:"follower_id"`    // who followed
	BoostedUserID uint          `gorm:"not null;index" json:"boosted_user_id"` // who was followed
	EarnAmount   float64        `gorm:"default:1.70" json:"earn_amount"`      // what follower earned
	FeeAmount    float64        `gorm:"default:0.30" json:"fee_amount"`       // platform fee
	Status       string         `gorm:"size:20;default:pending" json:"status"`
	PaidAt       *time.Time     `json:"paid_at"`
	CreatedAt    time.Time      `json:"created_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	Campaign     BoostCampaign `gorm:"foreignKey:CampaignID" json:"campaign,omitempty"`
	Follower     User          `gorm:"foreignKey:FollowerID" json:"follower,omitempty"`
	BoostedUser  User          `gorm:"foreignKey:BoostedUserID" json:"boosted_user,omitempty"`
}

// Story represents a 24-hour story
type Story struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	UserID      uint           `gorm:"not null;index" json:"user_id"`
	MediaURL    string         `gorm:"size:255;not null" json:"media_url"`
	MediaType   string         `gorm:"size:20" json:"media_type"` // video, image
	Caption     string         `gorm:"size:500" json:"caption"`
	ViewCount   int            `gorm:"default:0" json:"view_count"`
	Duration    int            `gorm:"default:5" json:"duration"` // seconds
	ExpiresAt   time.Time      `json:"expires_at"`
	CreatedAt   time.Time      `json:"created_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relationships
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}
