package websocket

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"gorm.io/gorm"

	"entertok-backend/models"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for development
	},
}

// ─── Message Type Constants ───────────────────────────────────────────────────
const (
	TypeChatMessage      = "chat_message"
	TypeGroupMessage     = "group_message"
	TypeTyping           = "typing"
	TypeOnlineStatus     = "online_status"
	TypeMessageRead      = "message_read"
	TypeMessageDelivered = "message_delivered"
	TypeMessageReaction  = "message_reaction"
	TypeNewPost          = "new_post"
	TypePostLiked        = "post_liked"
	TypePostUnliked      = "post_unliked"
	TypeNewComment       = "new_comment"
	TypeUserFollowed     = "user_followed"
	TypeUserUnfollowed   = "user_unfollowed"
	TypeNotification     = "notification"
	TypeLiveStart        = "live_start"
	TypeLiveEnd          = "live_end"
	TypeLiveComment      = "live_comment"
	TypeLiveViewerJoin   = "live_viewer_join"
	TypeLiveViewerLeave  = "live_viewer_leave"
	TypeLiveGift         = "live_gift"
	TypeStoryView        = "story_view"
	TypePing             = "ping"
	TypePong             = "pong"
	TypeError            = "error"
	// Group call signaling
	TypeGroupCallInvite  = "group_call_invite"
	TypeGroupCallJoin    = "group_call_join"
	TypeGroupCallDecline = "group_call_decline"
	TypeGroupCallEnd     = "group_call_end"
	// WebRTC Signaling
	TypeWebRTCOffer      = "webrtc_offer"
	TypeWebRTCAnswer     = "webrtc_answer"
	TypeWebRTCIce        = "webrtc_ice"
	TypeWebRTCCall       = "webrtc_call"
	TypeWebRTCReject     = "webrtc_reject"
	TypeWebRTCHangup     = "webrtc_hangup"
)

// ─── Payload Structs ──────────────────────────────────────────────────────────

type WebSocketMessage struct {
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload,omitempty"`
	Timestamp time.Time       `json:"timestamp"`
}

type ChatMessagePayload struct {
	ID             uint   `json:"id"`
	SenderID       uint   `json:"sender_id"`
	ReceiverID     uint   `json:"receiver_id"`
	Content        string `json:"content"`
	MediaURL       string `json:"media_url,omitempty"`
	MediaType      string `json:"media_type,omitempty"`
	ReplyToID      *uint  `json:"reply_to_id,omitempty"`
	ConversationID uint   `json:"conversation_id,omitempty"`
	SenderName     string `json:"sender_name,omitempty"`
	SenderAvatar   string `json:"sender_avatar,omitempty"`
}

type GroupMessagePayload struct {
	ID             uint   `json:"id"`
	SenderID       uint   `json:"sender_id"`
	SenderName     string `json:"sender_name"`
	SenderAvatar   string `json:"sender_avatar,omitempty"`
	GroupID        uint   `json:"group_id"`
	Content        string `json:"content"`
	MediaURL       string `json:"media_url,omitempty"`
	MediaType      string `json:"media_type,omitempty"`
	ConversationID uint   `json:"conversation_id,omitempty"`
}

type TypingPayload struct {
	FromUserID   uint   `json:"from_user_id"`
	FromUsername string `json:"from_username,omitempty"`
	ToUserID     uint   `json:"to_user_id"`
	GroupID      uint   `json:"group_id,omitempty"`
	IsTyping     bool   `json:"is_typing"`
}

type OnlineStatusPayload struct {
	UserID   uint   `json:"user_id"`
	Username string `json:"username,omitempty"`
	IsOnline bool   `json:"is_online"`
}

type MessageReadPayload struct {
	MessageID      uint `json:"message_id"`
	ReaderID       uint `json:"reader_id"`
	ConversationID uint `json:"conversation_id"`
}

type MessageReactionPayload struct {
	MessageID uint   `json:"message_id"`
	UserID    uint   `json:"user_id"`
	Emoji     string `json:"emoji"`
}

type NewPostPayload struct {
	ID        uint   `json:"id"`
	UserID    uint   `json:"user_id"`
	Content   string `json:"content"`
	MediaURL  string `json:"media_url"`
	MediaType string `json:"media_type"`
	Location  string `json:"location"`
	HashTags  string `json:"hash_tags"`
	LikeCount int    `json:"like_count"`
	ViewCount int    `json:"view_count"`
	Username  string `json:"username"`
	FullName  string `json:"full_name"`
	Avatar    string `json:"avatar,omitempty"`
}

type PostLikePayload struct {
	PostID    uint `json:"post_id"`
	UserID    uint `json:"user_id"`
	IsLiked   bool `json:"is_liked"`
	LikeCount int  `json:"like_count"`
}

type NewCommentPayload struct {
	ID       uint   `json:"id"`
	PostID   uint   `json:"post_id"`
	UserID   uint   `json:"user_id"`
	Content  string `json:"content"`
	Username string `json:"username"`
	FullName string `json:"full_name"`
	Avatar   string `json:"avatar,omitempty"`
}

type UserFollowPayload struct {
	FollowerID  uint `json:"follower_id"`
	FollowingID uint `json:"following_id"`
	IsFollowing bool `json:"is_following"`
}

type LiveStreamPayload struct {
	StreamID     uint   `json:"stream_id"`
	UserID       uint   `json:"user_id"`
	Username     string `json:"username"`
	FullName     string `json:"full_name"`
	Avatar       string `json:"avatar,omitempty"`
	Title        string `json:"title"`
	ViewerCount  int    `json:"viewer_count"`
	ThumbnailURL string `json:"thumbnail_url,omitempty"`
}

type LiveCommentPayload struct {
	StreamID    uint    `json:"stream_id"`
	UserID      uint    `json:"user_id"`
	Username    string  `json:"username"`
	Avatar      string  `json:"avatar,omitempty"`
	Content     string  `json:"content"`
	CommentType string  `json:"comment_type"` // text, gift, join
	GiftValue   float64 `json:"gift_value,omitempty"`
}

type NotificationPayload struct {
	ID      uint   `json:"id"`
	Type    string `json:"type"`
	Message string `json:"message"`
	ActorID uint   `json:"actor_id"`
	PostID  *uint  `json:"post_id,omitempty"`
	Actor   struct {
		Username string `json:"username"`
		Avatar   string `json:"avatar,omitempty"`
	} `json:"actor"`
}

// ─── Client ───────────────────────────────────────────────────────────────────

type Client struct {
	hub      *Hub
	conn     *websocket.Conn
	send     chan []byte
	user     *models.User
	streamID uint // if watching a live stream
}

// ─── Hub ──────────────────────────────────────────────────────────────────────

type Hub struct {
	clients    map[uint]*Client
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	mutex      sync.RWMutex
	db         *gorm.DB
	// WebRTC random matching
	webrtcWaiting []uint
	webrtcPairs   map[uint]uint
	webrtcMu      sync.RWMutex
	// Meeting rooms: code → host user ID (public for REST access)
	MeetingRooms map[string]uint
	MeetingMu    sync.RWMutex
}

func NewHub(db *gorm.DB) *Hub {
	return &Hub{
		clients:       make(map[uint]*Client),
		broadcast:     make(chan []byte, 512),
		register:      make(chan *Client, 64),
		unregister:    make(chan *Client, 64),
		db:            db,
		webrtcWaiting: []uint{},
		webrtcPairs:   make(map[uint]uint),
		MeetingRooms:  make(map[string]uint),
	}
}

var globalHub *Hub

func SetHub(hub *Hub) { globalHub = hub }
func GetHub() *Hub    { return globalHub }

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mutex.Lock()
			h.clients[client.user.ID] = client
			h.mutex.Unlock()
			// Mark user online in DB
			h.db.Model(&models.User{}).Where("id = ?", client.user.ID).
				Updates(map[string]interface{}{"is_online": true})
			h.broadcastOnlineStatus(client.user.ID, client.user.Username, true)
			log.Printf("🟢 WS CONNECT: user=%d @%s  total_online=%d",
				client.user.ID, client.user.Username, func() int {
					h.mutex.RLock(); defer h.mutex.RUnlock(); return len(h.clients)
				}())

		case client := <-h.unregister:
			h.mutex.Lock()
			if _, ok := h.clients[client.user.ID]; ok {
				delete(h.clients, client.user.ID)
				close(client.send)
			}
			h.mutex.Unlock()
			// Clean up WebRTC state
			h.webrtcMu.Lock()
			if partnerID, paired := h.webrtcPairs[client.user.ID]; paired {
				delete(h.webrtcPairs, client.user.ID)
				delete(h.webrtcPairs, partnerID)
				// Notify partner
				hangupData, _ := json.Marshal(map[string]interface{}{"from_user_id": client.user.ID})
				hangupMsg := WebSocketMessage{Type: TypeWebRTCHangup, Payload: hangupData, Timestamp: time.Now()}
				b, _ := json.Marshal(hangupMsg)
				h.SendToUser(partnerID, b)
			}
			// Remove from waiting queue
			for i, uid := range h.webrtcWaiting {
				if uid == client.user.ID {
					h.webrtcWaiting = append(h.webrtcWaiting[:i], h.webrtcWaiting[i+1:]...)
					break
				}
			}
			h.webrtcMu.Unlock()
			// Mark user offline in DB
			now := time.Now()
			h.db.Model(&models.User{}).Where("id = ?", client.user.ID).
				Updates(map[string]interface{}{"is_online": false, "last_seen_at": now})
			h.broadcastOnlineStatus(client.user.ID, client.user.Username, false)

		case message := <-h.broadcast:
			h.mutex.RLock()
			for _, client := range h.clients {
				select {
				case client.send <- message:
				default:
					// channel full — skip, don't block or delete under read lock
				}
			}
			h.mutex.RUnlock()
		}
	}
}

// ─── Send Helpers ─────────────────────────────────────────────────────────────

func (h *Hub) SendToUser(userID uint, message []byte) {
	h.mutex.RLock()
	client, ok := h.clients[userID]
	h.mutex.RUnlock()
	if ok {
		select {
		case client.send <- message:
			log.Printf("📨 SendToUser: delivered to user=%d", userID)
		default:
			log.Printf("⚠️  SendToUser: buffer full for user=%d", userID)
		}
	} else {
		log.Printf("🔴 SendToUser: user=%d NOT connected (clients=%v)", userID, func() []uint {
			h.mutex.RLock(); defer h.mutex.RUnlock()
			ids := make([]uint, 0, len(h.clients))
			for id := range h.clients { ids = append(ids, id) }
			return ids
		}())
	}
}

func (h *Hub) IsOnline(userID uint) bool {
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	_, ok := h.clients[userID]
	return ok
}

func (h *Hub) GetOnlineCount() int {
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	return len(h.clients)
}

func buildMsg(msgType string, payload interface{}) []byte {
	var raw json.RawMessage
	if payload != nil {
		b, _ := json.Marshal(payload)
		raw = b
	}
	msg := WebSocketMessage{Type: msgType, Payload: raw, Timestamp: time.Now()}
	data, _ := json.Marshal(msg)
	return data
}

// ─── Broadcast Methods ────────────────────────────────────────────────────────

func (h *Hub) broadcastOnlineStatus(userID uint, username string, isOnline bool) {
	data := buildMsg(TypeOnlineStatus, OnlineStatusPayload{
		UserID: userID, Username: username, IsOnline: isOnline,
	})
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for uid, client := range h.clients {
		if uid != userID {
			select {
			case client.send <- data:
			default:
			}
		}
	}
}

// BroadcastChatMessage broadcasts a direct message to the receiver and the sender
func (h *Hub) BroadcastChatMessage(senderID uint, senderName string, senderAvatar string, dbMsg *models.Message) {
	payload := ChatMessagePayload{
		ID:             dbMsg.ID,
		SenderID:       senderID,
		ReceiverID:     dbMsg.ReceiverID,
		Content:        dbMsg.Content,
		MediaURL:       dbMsg.MediaURL,
		MediaType:      dbMsg.MediaType,
		ReplyToID:      dbMsg.ReplyToID,
		ConversationID: dbMsg.ConversationID,
		SenderName:     senderName,
		SenderAvatar:   senderAvatar,
	}
	data := buildMsg(TypeChatMessage, payload)
	h.SendToUser(dbMsg.ReceiverID, data)
	h.SendToUser(senderID, data)
	h.sendToAdmins(data, senderID, dbMsg.ReceiverID)
}

// BroadcastGroupMessage broadcasts a group message to all group members
func (h *Hub) BroadcastGroupMessage(senderID uint, senderName string, senderAvatar string, dbMsg *models.Message) {
	payload := GroupMessagePayload{
		ID:             dbMsg.ID,
		SenderID:       senderID,
		SenderName:     senderName,
		SenderAvatar:   senderAvatar,
		GroupID:        dbMsg.GroupID,
		Content:        dbMsg.Content,
		MediaURL:       dbMsg.MediaURL,
		MediaType:      dbMsg.MediaType,
		ConversationID: dbMsg.ConversationID,
	}
	data := buildMsg(TypeGroupMessage, payload)
	h.BroadcastToGroup(dbMsg.GroupID, senderID, data)
	h.SendToUser(senderID, data)
}

func (h *Hub) BroadcastLiveStart(stream *models.LiveStream, user *models.User) {
	payload := LiveStreamPayload{
		StreamID:     stream.ID,
		UserID:       stream.UserID,
		Username:     user.Username,
		FullName:     user.FullName,
		Avatar:       user.ProfileImage,
		Title:        stream.Title,
		ThumbnailURL: stream.ThumbnailURL,
	}
	data := buildMsg(TypeLiveStart, payload)
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		if client.user.ID != stream.UserID {
			select {
			case client.send <- data:
			default:
			}
		}
	}
}

func (h *Hub) BroadcastLiveEnd(streamID uint) {
	type endPayload struct {
		StreamID uint `json:"stream_id"`
	}
	data := buildMsg(TypeLiveEnd, endPayload{StreamID: streamID})
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		select {
		case client.send <- data:
		default:
		}
	}
}

func (h *Hub) BroadcastNewPost(post *models.Post) {	var user models.User
	h.db.First(&user, post.UserID)
	data := buildMsg(TypeNewPost, NewPostPayload{
		ID: post.ID, UserID: post.UserID, Content: post.Content,
		MediaURL: post.MediaURL, MediaType: post.MediaType,
		Location: post.Location, HashTags: post.HashTags,
		LikeCount: post.LikeCount, ViewCount: post.ViewCount,
		Username: user.Username, FullName: user.FullName,
		Avatar: user.ProfileImage,
	})
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		select {
		case client.send <- data:
		default:
		}
	}
}

func (h *Hub) BroadcastPostLike(postID uint, userID uint, isLiked bool, likeCount int) {
	msgType := TypePostLiked
	if !isLiked {
		msgType = TypePostUnliked
	}
	data := buildMsg(msgType, PostLikePayload{
		PostID: postID, UserID: userID, IsLiked: isLiked, LikeCount: likeCount,
	})
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		select {
		case client.send <- data:
		default:
		}
	}
}

func (h *Hub) BroadcastNewComment(comment *models.Comment) {
	var user models.User
	h.db.First(&user, comment.UserID)
	data := buildMsg(TypeNewComment, NewCommentPayload{
		ID: comment.ID, PostID: comment.PostID, UserID: comment.UserID,
		Content: comment.Content, Username: user.Username,
		FullName: user.FullName, Avatar: user.ProfileImage,
	})
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		select {
		case client.send <- data:
		default:
		}
	}
}

func (h *Hub) SendNotification(userID uint, notif *models.Notification) {
	var actor models.User
	h.db.First(&actor, notif.ActorID)
	payload := NotificationPayload{
		ID: notif.ID, Type: notif.Type, Message: notif.Message,
		ActorID: notif.ActorID, PostID: notif.PostID,
	}
	payload.Actor.Username = actor.Username
	payload.Actor.Avatar = actor.ProfileImage
	data := buildMsg(TypeNotification, payload)
	h.SendToUser(userID, data)
}

func (h *Hub) BroadcastToGroup(groupID uint, senderID uint, message []byte) {
	// Query members WITHOUT holding the mutex to avoid slow DB calls under lock
	var members []models.GroupMember
	h.db.Where("conversation_id = ?", groupID).Find(&members)
	memberIDs := make(map[uint]bool, len(members))
	for _, m := range members {
		memberIDs[m.UserID] = true
	}
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for userID, client := range h.clients {
		if userID != senderID && memberIDs[userID] {
			select {
			case client.send <- message:
			default:
			}
		}
	}
}

func (h *Hub) BroadcastToLiveViewers(streamID uint, hostID uint, message []byte) {
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for _, client := range h.clients {
		if client.streamID == streamID || client.user.ID == hostID {
			select {
			case client.send <- message:
			default:
			}
		}
	}
}

// BroadcastChatToAdmins is a public wrapper for admin monitoring
func (h *Hub) BroadcastChatToAdmins(data []byte, excludeIDs ...uint) {
	h.sendToAdmins(data, excludeIDs...)
}
// excluding the given user IDs (sender and receiver already got it)
func (h *Hub) sendToAdmins(data []byte, excludeIDs ...uint) {
	exclude := make(map[uint]bool, len(excludeIDs))
	for _, id := range excludeIDs {
		exclude[id] = true
	}
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	for uid, client := range h.clients {
		if exclude[uid] {
			continue
		}
		if client.user.Role == "admin" {
			select {
			case client.send <- data:
			default:
			}
		}
	}
}

// ─── Message Handler ──────────────────────────────────────────────────────────

func (h *Hub) handleMessage(client *Client, msgType string, payload json.RawMessage) {
	switch msgType {
	case TypePing:
		client.send <- buildMsg(TypePong, nil)

	// ── Meeting room: host registers, joiner gets host's real user ID ─────
	case "meeting_host":
		// Host registers their presence in a room
		var p struct { Code string `json:"code"` }
		if err := json.Unmarshal(payload, &p); err != nil { return }
		h.MeetingMu.Lock()
		h.MeetingRooms[p.Code] = client.user.ID
		h.MeetingMu.Unlock()
		log.Printf("🏠 Meeting host: user=%d code=%s", client.user.ID, p.Code)
		// Ack
		ack, _ := json.Marshal(map[string]interface{}{"code": p.Code, "status": "hosting"})
		client.send <- buildMsg("meeting_hosting", ack)

	case "meeting_join":
		// Joiner asks: who is the host for this code?
		var p struct { Code string `json:"code"` }
		if err := json.Unmarshal(payload, &p); err != nil { return }
		h.MeetingMu.RLock()
		hostID, exists := h.MeetingRooms[p.Code]
		h.MeetingMu.RUnlock()
		if !exists || hostID == 0 {
			// No host yet — tell joiner to wait
			noHost, _ := json.Marshal(map[string]interface{}{"code": p.Code, "status": "no_host"})
			client.send <- buildMsg("meeting_join_result", noHost)
			return
		}
		// Load host info
		var host models.User
		h.db.First(&host, hostID)
		result, _ := json.Marshal(map[string]interface{}{
			"code":        p.Code,
			"status":      "found",
			"host_id":     hostID,
			"host_name":   host.FullName,
			"host_avatar": host.ProfileImage,
		})
		client.send <- buildMsg("meeting_join_result", result)
		// Also notify host that someone joined
		joinNotify, _ := json.Marshal(map[string]interface{}{
			"code":         p.Code,
			"joiner_id":    client.user.ID,
			"joiner_name":  client.user.FullName,
			"joiner_avatar": client.user.ProfileImage,
		})
		h.SendToUser(hostID, buildMsg("meeting_joiner", joinNotify))
		log.Printf("🤝 Meeting join: joiner=%d → host=%d code=%s", client.user.ID, hostID, p.Code)

	case "meeting_leave":
		// Host/joiner leaving — clean up room
		var p struct { Code string `json:"code"` }
		if err := json.Unmarshal(payload, &p); err != nil { return }
		h.MeetingMu.Lock()
		if h.MeetingRooms[p.Code] == client.user.ID {
			delete(h.MeetingRooms, p.Code)
		}
		h.MeetingMu.Unlock()

	// ── WebRTC Random Matching ────────────────────────────────────────────
	case "webrtc_find_peer":
		// Add user to waiting room — or match with someone already waiting
		h.webrtcMu.Lock()
		if len(h.webrtcWaiting) > 0 && h.webrtcWaiting[0] != client.user.ID {
			// Match found — pop from queue
			partnerID := h.webrtcWaiting[0]
			h.webrtcWaiting = h.webrtcWaiting[1:]
			h.webrtcPairs[client.user.ID] = partnerID
			h.webrtcPairs[partnerID] = client.user.ID
			h.webrtcMu.Unlock()

			// Tell each peer who their partner is & who should initiate
			matchPayload := func(peerID uint, shouldOffer bool) []byte {
				var peer models.User
				h.db.First(&peer, peerID)
				data, _ := json.Marshal(map[string]interface{}{
					"peer_id":      peerID,
					"peer_name":    peer.FullName,
					"peer_avatar":  peer.ProfileImage,
					"should_offer": shouldOffer,
				})
				msg := WebSocketMessage{Type: "webrtc_matched", Payload: data, Timestamp: time.Now()}
				b, _ := json.Marshal(msg)
				return b
			}
			h.SendToUser(client.user.ID, matchPayload(partnerID, true))  // caller creates offer
			h.SendToUser(partnerID, matchPayload(client.user.ID, false)) // callee waits for offer
		} else {
			// No partner yet — add to queue
			h.webrtcWaiting = append(h.webrtcWaiting, client.user.ID)
			h.webrtcMu.Unlock()
			// Tell client they're waiting
			data, _ := json.Marshal(map[string]string{"status": "waiting"})
			msg := WebSocketMessage{Type: "webrtc_waiting", Payload: data, Timestamp: time.Now()}
			b, _ := json.Marshal(msg)
			client.send <- b
		}

	case "webrtc_cancel_find":
		// Remove from waiting room
		h.webrtcMu.Lock()
		for i, uid := range h.webrtcWaiting {
			if uid == client.user.ID {
				h.webrtcWaiting = append(h.webrtcWaiting[:i], h.webrtcWaiting[i+1:]...)
				break
			}
		}
		h.webrtcMu.Unlock()

	// ── WebRTC P2P Signaling (offer/answer/ice/hangup) ────────────────────
	case TypeWebRTCOffer, TypeWebRTCAnswer, TypeWebRTCIce, TypeWebRTCReject, TypeWebRTCHangup:
		var sig struct {
			ToUserID uint            `json:"to_user_id"`
			Data     json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal(payload, &sig); err != nil {
			return
		}
		// Look up peer from the pair map if to_user_id is 0
		targetID := sig.ToUserID
		if targetID == 0 {
			h.webrtcMu.RLock()
			targetID = h.webrtcPairs[client.user.ID]
			h.webrtcMu.RUnlock()
		}
		if targetID == 0 {
			return
		}
		// Inject sender info
		enriched, _ := json.Marshal(map[string]interface{}{
			"from_user_id": client.user.ID,
			"from_name":    client.user.FullName,
			"to_user_id":   targetID,
			"data":         sig.Data,
		})
		fwdMsg := WebSocketMessage{Type: msgType, Payload: enriched, Timestamp: time.Now()}
		fwdData, _ := json.Marshal(fwdMsg)
		h.SendToUser(targetID, fwdData)

		// On hangup, clean up pair
		if msgType == TypeWebRTCHangup {
			h.webrtcMu.Lock()
			delete(h.webrtcPairs, client.user.ID)
			delete(h.webrtcPairs, targetID)
			h.webrtcMu.Unlock()
		}

	// ── Chat overlay during video call ────────────────────────────────────
	case TypeWebRTCCall:
		var sig struct {
			ToUserID uint   `json:"to_user_id"`
			Content  string `json:"content"`
		}
		if err := json.Unmarshal(payload, &sig); err != nil { return }
		if sig.ToUserID == 0 {
			// Fall back to pair map if to_user_id not set
			h.webrtcMu.RLock()
			sig.ToUserID = h.webrtcPairs[client.user.ID]
			h.webrtcMu.RUnlock()
		}
		if sig.ToUserID == 0 { return }
		enriched, _ := json.Marshal(map[string]interface{}{
			"from_user_id": client.user.ID,
			"from_name":    client.user.FullName,
			"from_avatar":  client.user.ProfileImage,
			"content":      sig.Content,  // ← was missing!
		})
		fwdMsg := WebSocketMessage{Type: "webrtc_chat", Payload: enriched, Timestamp: time.Now()}
		fwdData, _ := json.Marshal(fwdMsg)
		h.SendToUser(sig.ToUserID, fwdData)

	// ── Typing indicator during video call ────────────────────────────────
	case "webrtc_typing":
		var sig struct {
			ToUserID  uint `json:"to_user_id"`
			IsTyping  bool `json:"is_typing"`
		}
		if err := json.Unmarshal(payload, &sig); err != nil { return }
		if sig.ToUserID == 0 {
			h.webrtcMu.RLock()
			sig.ToUserID = h.webrtcPairs[client.user.ID]
			h.webrtcMu.RUnlock()
		}
		if sig.ToUserID == 0 { return }
		typingData, _ := json.Marshal(map[string]interface{}{
			"from_user_id": client.user.ID,
			"is_typing":    sig.IsTyping,
		})
		typingMsg := WebSocketMessage{Type: "webrtc_typing", Payload: typingData, Timestamp: time.Now()}
		typingFwd, _ := json.Marshal(typingMsg)
		h.SendToUser(sig.ToUserID, typingFwd)

	case TypeGroupCallInvite:
		var p struct {
			GroupID   uint   `json:"group_id"`
			GroupName string `json:"group_name"`
			CallType  string `json:"call_type"`
		}
		if err := json.Unmarshal(payload, &p); err != nil { return }
		invite := map[string]interface{}{
			"group_id":      p.GroupID,
			"group_name":    p.GroupName,
			"call_type":     p.CallType,
			"caller_id":     client.user.ID,
			"caller_name":   client.user.FullName,
			"caller_avatar": client.user.ProfileImage,
		}
		data := buildMsg(TypeGroupCallInvite, invite)
		var members []models.GroupMember
		h.db.Where("conversation_id = ?", p.GroupID).Find(&members)
		for _, m := range members {
			if m.UserID != client.user.ID {
				h.SendToUser(m.UserID, data)
			}
		}
		h.sendToAdmins(data, client.user.ID)

	case TypeGroupCallJoin:
		var p struct {
			GroupID  uint `json:"group_id"`
			CallerID uint `json:"caller_id"`
		}
		if err := json.Unmarshal(payload, &p); err != nil { return }
		joinMsg := map[string]interface{}{
			"group_id":      p.GroupID,
			"joiner_id":     client.user.ID,
			"joiner_name":   client.user.FullName,
			"joiner_avatar": client.user.ProfileImage,
		}
		h.SendToUser(p.CallerID, buildMsg(TypeGroupCallJoin, joinMsg))

	case TypeGroupCallDecline:
		var p struct {
			GroupID  uint `json:"group_id"`
			CallerID uint `json:"caller_id"`
		}
		if err := json.Unmarshal(payload, &p); err != nil { return }
		h.SendToUser(p.CallerID, buildMsg(TypeGroupCallDecline, map[string]interface{}{
			"group_id":     p.GroupID,
			"decliner_id":  client.user.ID,
			"decliner_name": client.user.FullName,
		}))

	case TypeGroupCallEnd:
		var p struct { GroupID uint `json:"group_id"` }
		if err := json.Unmarshal(payload, &p); err != nil { return }
		endMsg := buildMsg(TypeGroupCallEnd, map[string]interface{}{
			"group_id": p.GroupID, "ender_id": client.user.ID,
		})
		var members []models.GroupMember
		h.db.Where("conversation_id = ?", p.GroupID).Find(&members)
		for _, m := range members {
			if m.UserID != client.user.ID {
				h.SendToUser(m.UserID, endMsg)
			}
		}

	case TypeChatMessage:
		var msg ChatMessagePayload
		if err := json.Unmarshal(payload, &msg); err != nil {
			return
		}

		// Find or create conversation if it doesn't exist or is 0
		var conversationID = msg.ConversationID
		if conversationID == 0 {
			var conversation models.Conversation
			h.db.Where("(participant1 = ? AND participant2 = ?) OR (participant1 = ? AND participant2 = ?)",
				client.user.ID, msg.ReceiverID, msg.ReceiverID, client.user.ID).
				First(&conversation)

			if conversation.ID == 0 {
				conversation = models.Conversation{
					Participant1: client.user.ID,
					Participant2: msg.ReceiverID,
				}
				h.db.Create(&conversation)
			}
			conversationID = conversation.ID
			msg.ConversationID = conversationID
		}

		// Persist to DB
		dbMsg := models.Message{
			SenderID:       client.user.ID,
			ReceiverID:     msg.ReceiverID,
			Content:        msg.Content,
			MediaURL:       msg.MediaURL,
			MediaType:      msg.MediaType,
			ReplyToID:      msg.ReplyToID,
			ConversationID: conversationID,
			IsDelivered:    true,
		}
		h.db.Create(&dbMsg)
		msg.ID = dbMsg.ID
		msg.SenderID = client.user.ID
		msg.SenderName = client.user.FullName
		msg.SenderAvatar = client.user.ProfileImage

		// Update conversation last message
		now := time.Now()
		h.db.Model(&models.Conversation{}).Where("id = ?", conversationID).
			Updates(map[string]interface{}{"last_message_id": dbMsg.ID, "last_message_at": now})

		data := buildMsg(TypeChatMessage, msg)
		log.Printf("💬 WS chat: sender=%d → receiver=%d  content=%q  online_clients=%d",
			msg.SenderID, msg.ReceiverID, msg.Content, len(h.clients))
		h.SendToUser(msg.ReceiverID, data)
		// NOTE: No echo to sender — Flutter uses optimistic bubble already
		// Also send to any admin users monitoring the platform
		h.sendToAdmins(data, client.user.ID, msg.ReceiverID)

	case TypeGroupMessage:
		var msg GroupMessagePayload
		if err := json.Unmarshal(payload, &msg); err != nil {
			return
		}
		dbMsg := models.Message{
			SenderID:       client.user.ID,
			Content:        msg.Content,
			MediaURL:       msg.MediaURL,
			MediaType:      msg.MediaType,
			ConversationID: msg.ConversationID,
			IsGroup:        true,
			GroupID:        msg.GroupID,
			IsDelivered:    true,
		}
		h.db.Create(&dbMsg)
		msg.ID = dbMsg.ID
		msg.SenderID = client.user.ID
		msg.SenderName = client.user.FullName
		msg.SenderAvatar = client.user.ProfileImage

		data := buildMsg(TypeGroupMessage, msg)
		h.BroadcastToGroup(msg.GroupID, client.user.ID, data)
		client.send <- data

	case TypeTyping:
		var t TypingPayload
		if err := json.Unmarshal(payload, &t); err != nil {
			return
		}
		t.FromUserID = client.user.ID
		t.FromUsername = client.user.Username
		data := buildMsg(TypeTyping, t)
		if t.GroupID > 0 {
			h.BroadcastToGroup(t.GroupID, client.user.ID, data)
		} else {
			h.SendToUser(t.ToUserID, data)
			// Forward typing to admins too
			h.sendToAdmins(data, client.user.ID, t.ToUserID)
		}

	case TypeMessageRead:
		var r MessageReadPayload
		if err := json.Unmarshal(payload, &r); err != nil {
			return
		}
		h.db.Model(&models.Message{}).Where("id = ?", r.MessageID).Update("is_read", true)
		data := buildMsg(TypeMessageRead, r)
		// Notify the original sender
		var msg models.Message
		if h.db.First(&msg, r.MessageID).Error == nil {
			h.SendToUser(msg.SenderID, data)
		}

	case TypeMessageReaction:
		var r MessageReactionPayload
		if err := json.Unmarshal(payload, &r); err != nil {
			return
		}
		r.UserID = client.user.ID
		data := buildMsg(TypeMessageReaction, r)
		var msg models.Message
		if h.db.First(&msg, r.MessageID).Error == nil {
			h.SendToUser(msg.SenderID, data)
			h.SendToUser(msg.ReceiverID, data)
		}

	case TypeLiveComment:
		var lc LiveCommentPayload
		if err := json.Unmarshal(payload, &lc); err != nil {
			return
		}
		lc.UserID = client.user.ID
		lc.Username = client.user.Username
		lc.Avatar = client.user.ProfileImage
		// Persist live comment
		dbComment := models.LiveComment{
			StreamID:    lc.StreamID,
			UserID:      client.user.ID,
			Content:     lc.Content,
			CommentType: lc.CommentType,
			GiftValue:   lc.GiftValue,
		}
		h.db.Create(&dbComment)
		data := buildMsg(TypeLiveComment, lc)
		// Get stream host
		var stream models.LiveStream
		if h.db.First(&stream, lc.StreamID).Error == nil {
			h.BroadcastToLiveViewers(lc.StreamID, stream.UserID, data)
		}

	case TypeLiveViewerJoin:
		var lv struct {
			StreamID uint `json:"stream_id"`
		}
		if err := json.Unmarshal(payload, &lv); err != nil {
			return
		}
		client.streamID = lv.StreamID
		// Increment viewer count
		h.db.Model(&models.LiveStream{}).Where("id = ?", lv.StreamID).
			UpdateColumn("viewer_count", gorm.Expr("viewer_count + ?", 1))
		var stream models.LiveStream
		h.db.First(&stream, lv.StreamID)
		data := buildMsg(TypeLiveViewerJoin, LiveCommentPayload{
			StreamID: lv.StreamID, UserID: client.user.ID,
			Username: client.user.Username, Avatar: client.user.ProfileImage,
			Content: client.user.Username + " joined", CommentType: "join",
		})
		h.BroadcastToLiveViewers(lv.StreamID, stream.UserID, data)

	case TypeLiveViewerLeave:
		var lv struct {
			StreamID uint `json:"stream_id"`
		}
		if err := json.Unmarshal(payload, &lv); err != nil {
			return
		}
		client.streamID = 0
		h.db.Model(&models.LiveStream{}).Where("id = ?", lv.StreamID).
			UpdateColumn("viewer_count", gorm.Expr("viewer_count - ?", 1))
	}
}

// ─── WebSocket Connection ─────────────────────────────────────────────────────

func (h *Hub) HandleWebSocket(w http.ResponseWriter, r *http.Request, user *models.User) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}
	client := &Client{
		hub:  h,
		conn: conn,
		send: make(chan []byte, 512),
		user: user,
	}
	h.register <- client
	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadLimit(1 << 20) // 1MB
	c.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		return nil
	})
	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			break
		}
		var wsMsg WebSocketMessage
		if err := json.Unmarshal(message, &wsMsg); err != nil {
			continue
		}
		c.hub.handleMessage(c, wsMsg.Type, wsMsg.Payload)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}
			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
