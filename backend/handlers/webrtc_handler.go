package handlers

// WebRTC signaling is handled entirely through the WebSocket hub.
// Clients send/receive offer, answer, and ICE candidates via WebSocket messages.
// No additional HTTP handlers needed — signaling types are:
//   webrtc_offer    { to_user_id, sdp }
//   webrtc_answer   { to_user_id, sdp }
//   webrtc_ice      { to_user_id, candidate }
//   webrtc_call     { to_user_id, from_user_id, caller_name }
//   webrtc_reject   { to_user_id }
//   webrtc_hangup   { to_user_id }
// These are forwarded peer-to-peer through the hub's SendToUser method.
