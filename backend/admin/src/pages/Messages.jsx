import React, { useState, useEffect, useRef, useCallback } from 'react'
import api from '../api'
import toast from 'react-hot-toast'
import {
  MessageSquare, RefreshCw, Search, Send,
  Users, Image as ImgIcon, X, Wifi, WifiOff
} from 'lucide-react'

// ── helpers ───────────────────────────────────────────────────────────────────
const fmt = ts => {
  if (!ts) return ''
  const d = new Date(ts)
  const now = new Date()
  return d.toDateString() === now.toDateString()
    ? d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString([], { month: 'short', day: 'numeric', hour:'2-digit', minute:'2-digit' })
}

function Ava({ user, size = 36 }) {
  const COLS = ['#7c3aed','#ec4899','#3b82f6','#22c55e','#f59e0b','#ef4444','#06b6d4']
  const bg   = COLS[((user?.id || 0)) % COLS.length]
  const name = user?.full_name || user?.username || '?'
  const src  = user?.profile_image
    ? (user.profile_image.startsWith('http') ? user.profile_image : `/uploads/${user.profile_image}`)
    : null
  if (src) return <img src={src} style={{ width:size,height:size,borderRadius:'50%',objectFit:'cover',flexShrink:0 }} alt="" onError={e=>e.target.style.display='none'}/>
  return (
    <div style={{ width:size,height:size,borderRadius:'50%',background:bg,display:'flex',alignItems:'center',justifyContent:'center',color:'#fff',fontWeight:700,fontSize:size*0.38,flexShrink:0 }}>
      {name[0].toUpperCase()}
    </div>
  )
}

// ── useAdminWS — WebSocket hook for admin ─────────────────────────────────────
function useAdminWS(onMessage) {
  const [connected, setConnected] = useState(false)
  const wsRef   = useRef(null)
  const timerRef = useRef(null)

  const connect = useCallback(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) return
    try {
      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws?token=${token}`);
      wsRef.current = ws

      ws.onopen  = () => { setConnected(true);  clearTimeout(timerRef.current) }
      ws.onclose = () => {
        setConnected(false)
        // Reconnect after 3 seconds
        timerRef.current = setTimeout(connect, 3000)
      }
      ws.onerror = () => ws.close()
      ws.onmessage = e => {
        try {
          const raw = JSON.parse(e.data)
          onMessage(raw)
        } catch {}
      }
    } catch {}
  }, [onMessage])

  useEffect(() => {
    connect()
    return () => {
      clearTimeout(timerRef.current)
      wsRef.current?.close()
    }
  }, [connect])

  const send = useCallback(payload => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(payload))
    }
  }, [])

  return { connected, send }
}

// ── Main component ────────────────────────────────────────────────────────────
export default function Messages() {
  const [convos, setConvos]         = useState([])
  const [total, setTotal]           = useState(0)
  const [convLoading, setConvLoading] = useState(true)
  const [search, setSearch]         = useState('')

  const [selected, setSelected]     = useState(null)
  const [messages, setMessages]     = useState([])
  const [p1, setP1]                 = useState(null)
  const [p2, setP2]                 = useState(null)
  const [msgLoading, setMsgLoading] = useState(false)

  const [sendText, setSendText]     = useState('')
  const [sending, setSending]       = useState(false)
  const [sendAsId, setSendAsId]     = useState(null)

  // Typing indicators: map of userId → bool
  const [typing, setTyping]         = useState({})

  const bottomRef  = useRef(null)
  const inputRef   = useRef(null)
  const selectedRef = useRef(null)   // keep latest selected in WS handler
  const p1Ref      = useRef(null)
  const p2Ref      = useRef(null)

  // Keep refs in sync
  useEffect(() => { selectedRef.current = selected }, [selected])
  useEffect(() => { p1Ref.current = p1; p2Ref.current = p2 }, [p1, p2])

  // ── WebSocket handler ──────────────────────────────────────────────────
  const handleWsMsg = useCallback(raw => {
    const type    = raw?.type
    const payload = raw?.payload

    if (type === 'chat_message' && payload) {
      const conv = selectedRef.current
      if (!conv) return
      const u1 = p1Ref.current
      const u2 = p2Ref.current
      // Check if this message belongs to the open conversation
      const belongsHere = (
        (payload.sender_id === u1?.id || payload.sender_id === u2?.id) &&
        (payload.receiver_id === u1?.id || payload.receiver_id === u2?.id)
      )
      if (!belongsHere) {
        // Update unread count / last message in sidebar
        setConvos(prev => prev.map(c => {
          const cu1id = c.participant1?.id
          const cu2id = c.participant2?.id
          if ((payload.sender_id===cu1id||payload.sender_id===cu2id) &&
              (payload.receiver_id===cu1id||payload.receiver_id===cu2id)) {
            return { ...c, last_message: payload.content, last_message_at: new Date().toISOString() }
          }
          return c
        }))
        return
      }

      const newMsg = {
        id:          payload.id || (Date.now() + Math.random()),
        content:     payload.content || '',
        sender_id:   payload.sender_id,
        receiver_id: payload.receiver_id,
        media_url:   payload.media_url,
        media_type:  payload.media_type,
        is_read:     false,
        created_at:  payload.created_at || new Date().toISOString(),
        sender: {
          id:            payload.sender_id,
          username:      payload.sender_name || '',
          full_name:     payload.sender_name || '',
          profile_image: payload.sender_avatar || '',
        },
      }

      setMessages(prev => {
        // Deduplicate by id
        if (prev.some(m => m.id === newMsg.id)) return prev
        return [...prev, newMsg]
      })

      // Update sidebar last_message
      setConvos(prev => prev.map(c =>
        c.id === conv.id
          ? { ...c, last_message: payload.content, last_message_at: new Date().toISOString() }
          : c
      ))
    }

    if (type === 'typing' && payload) {
      const fromId = payload.from_user_id || payload.user_id
      if (!fromId) return
      setTyping(prev => ({ ...prev, [fromId]: payload.is_typing }))
      // Auto-clear after 3s
      setTimeout(() => setTyping(prev => ({ ...prev, [fromId]: false })), 3000)
    }

    if (type === 'message_read' && payload) {
      setMessages(prev => prev.map(m =>
        m.id === payload.message_id ? { ...m, is_read: true } : m
      ))
    }
  }, [])

  const { connected } = useAdminWS(handleWsMsg)

  // ── Load conversations ─────────────────────────────────────────────────
  const loadConvos = useCallback(async (q = '') => {
    setConvLoading(true)
    try {
      const data = await api.get('/admin/conversations', { params: { q, page:1, page_size:50 } })
      setConvos(data?.conversations || [])
      setTotal(data?.total || 0)
    } catch (e) {
      toast.error('Failed to load: ' + (e?.error || e?.message || 'Check backend'))
    } finally {
      setConvLoading(false)
    }
  }, [])

  useEffect(() => { loadConvos() }, [loadConvos])
  useEffect(() => {
    const t = setTimeout(() => loadConvos(search), 300)
    return () => clearTimeout(t)
  }, [search, loadConvos])

  // ── Load messages ──────────────────────────────────────────────────────
  const loadMessages = useCallback(async (conv) => {
    setSelected(conv)
    setP1(conv.participant1)
    setP2(conv.participant2)
    setSendAsId(conv.participant1?.id)
    setSendText('')
    setMsgLoading(true)
    try {
      const data = await api.get(`/admin/conversations/${conv.id}/messages`, {
        params: { page:1, page_size:100 }
      })
      setMessages(data?.messages || [])
    } catch {
      toast.error('Failed to load messages')
      setMessages([])
    } finally {
      setMsgLoading(false)
    }
  }, [])

  // Auto-scroll on new message
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // ── Send ───────────────────────────────────────────────────────────────
  const handleSend = async () => {
    if (!sendText.trim() || !selected || !sendAsId) return
    const receiverId = sendAsId === p1?.id ? p2?.id : p1?.id
    if (!receiverId) return
    const text = sendText.trim()
    setSendText('')
    setSending(true)
    try {
      const msg = await api.post('/admin/messages/send', {
        sender_id:   sendAsId,
        receiver_id: receiverId,
        content:     text,
      })
      // Add optimistic message (WS echo might also arrive — dedup handles it)
      const senderUser = sendAsId === p1?.id ? p1 : p2
      setMessages(prev => {
        const newMsg = {
          id:          msg.id || Date.now(),
          content:     text,
          sender_id:   sendAsId,
          receiver_id: receiverId,
          is_read:     false,
          created_at:  new Date().toISOString(),
          sender:      msg.sender || senderUser,
        }
        if (prev.some(m => m.id === newMsg.id)) return prev
        return [...prev, newMsg]
      })
      setConvos(prev => prev.map(c =>
        c.id === selected.id ? { ...c, last_message: text, last_message_at: new Date().toISOString() } : c
      ))
    } catch (e) {
      setSendText(text) // restore on failure
      toast.error('Failed to send: ' + (e?.error || 'Unknown'))
    } finally {
      setSending(false)
      inputRef.current?.focus()
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────
  const handleDeleteMsg = async (msgId) => {
    if (!confirm('Delete this message?')) return
    try {
      await api.delete(`/admin/messages/${msgId}`)
      setMessages(prev => prev.filter(m => m.id !== msgId))
      toast.success('Deleted')
    } catch { toast.error('Delete failed') }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <div style={{ display:'flex', flexDirection:'column', height:'calc(100vh - 110px)' }}>

      {/* Page header */}
      <div className="page-header" style={{ marginBottom:14 }}>
        <div>
          <div className="page-title">Messages</div>
          <div className="page-subtitle" style={{ display:'flex', alignItems:'center', gap:8 }}>
            {total} conversations
            <span style={{
              display:'inline-flex', alignItems:'center', gap:4,
              padding:'2px 8px', borderRadius:20, fontSize:11,
              background: connected ? 'rgba(34,197,94,0.15)' : 'rgba(239,68,68,0.15)',
              color: connected ? 'var(--green)' : 'var(--red)',
              fontWeight:600
            }}>
              {connected ? <Wifi size={11}/> : <WifiOff size={11}/>}
              {connected ? 'Live' : 'Reconnecting…'}
            </span>
          </div>
        </div>
        <button className="btn btn-ghost" onClick={() => loadConvos(search)}>
          <RefreshCw size={14}/> Refresh
        </button>
      </div>

      {/* Main layout */}
      <div style={{ display:'grid', gridTemplateColumns:'300px 1fr', gap:16, flex:1, minHeight:0 }}>

        {/* ── Sidebar: conversations list ── */}
        <div style={{ display:'flex', flexDirection:'column', background:'var(--surface)', border:'1px solid var(--border)', borderRadius:'var(--radius)', overflow:'hidden' }}>

          {/* Search */}
          <div style={{ padding:'10px 12px', borderBottom:'1px solid var(--border)' }}>
            <div className="search-bar">
              <Search size={13}/>
              <input type="search" placeholder="Search users…" value={search}
                onChange={e => setSearch(e.target.value)}
                style={{ fontSize:13 }}/>
            </div>
          </div>

          {/* List */}
          <div style={{ overflowY:'auto', flex:1 }}>
            {convLoading ? (
              <div className="loading" style={{ padding:'30px 0' }}>
                <RefreshCw size={15} style={{ animation:'spin 1s linear infinite' }}/>
                Loading…
              </div>
            ) : convos.length === 0 ? (
              <div className="empty" style={{ padding:'30px 0' }}>
                <MessageSquare size={32}/><p>No conversations</p>
              </div>
            ) : convos.map(c => {
              const isActive = selected?.id === c.id
              const u1 = c.participant1 || {}
              const u2 = c.participant2 || {}
              return (
                <div key={c.id}
                  onClick={() => loadMessages(c)}
                  style={{
                    display:'flex', alignItems:'center', gap:10,
                    padding:'10px 12px', cursor:'pointer',
                    background: isActive ? 'rgba(124,58,237,0.12)' : 'transparent',
                    borderBottom:'1px solid var(--border)',
                    borderLeft: isActive ? '3px solid var(--accent)' : '3px solid transparent',
                    transition:'background 0.1s'
                  }}
                >
                  {/* Stacked avatars */}
                  <div style={{ position:'relative', width:38, height:38, flexShrink:0 }}>
                    <Ava user={u1} size={28}/>
                    <div style={{ position:'absolute', bottom:0, right:0 }}>
                      <Ava user={u2} size={22}/>
                    </div>
                  </div>

                  <div style={{ flex:1, minWidth:0 }}>
                    <div style={{ fontWeight:600, fontSize:12, display:'flex', gap:4, flexWrap:'nowrap' }}>
                      <span className="truncate" style={{ color:'var(--text)' }}>
                        {u1.full_name||u1.username||'?'}
                      </span>
                      <span style={{ color:'var(--text3)', fontWeight:400 }}>↔</span>
                      <span className="truncate" style={{ color:'var(--text)' }}>
                        {u2.full_name||u2.username||'?'}
                      </span>
                    </div>
                    <div style={{ color:'var(--text3)', fontSize:11, marginTop:2, display:'flex', justifyContent:'space-between' }}>
                      <span className="truncate" style={{ maxWidth:160 }}>{c.last_message || 'No messages'}</span>
                      <span style={{ flexShrink:0, marginLeft:4 }}>{fmt(c.last_message_at)}</span>
                    </div>
                    {c.message_count > 0 && (
                      <div style={{ fontSize:10, color:'var(--text3)', marginTop:2 }}>
                        {c.message_count} messages
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* ── Right panel: message thread ── */}
        <div style={{ display:'flex', flexDirection:'column', background:'var(--surface)', border:'1px solid var(--border)', borderRadius:'var(--radius)', overflow:'hidden' }}>

          {!selected ? (
            <div className="empty" style={{ flex:1 }}>
              <MessageSquare size={48}/>
              <p style={{ fontSize:15 }}>Select a conversation</p>
              <p style={{ fontSize:12, color:'var(--text3)' }}>Click any conversation on the left to view messages</p>
            </div>
          ) : (
            <>
              {/* Thread header */}
              <div style={{ padding:'12px 16px', borderBottom:'1px solid var(--border)', display:'flex', alignItems:'center', gap:12 }}>
                {/* Left person */}
                <div style={{ display:'flex', alignItems:'center', gap:6 }}>
                  <Ava user={p1} size={32}/>
                  <div>
                    <div style={{ fontWeight:700, fontSize:13 }}>{p1?.full_name || p1?.username}</div>
                    <div style={{ fontSize:10, color: sendAsId===p1?.id ? 'var(--accent2)' : 'var(--text3)' }}>
                      {sendAsId===p1?.id ? '◀ viewing as this user' : '@'+p1?.username}
                    </div>
                  </div>
                </div>

                <div style={{ padding:'4px 10px', background:'var(--surface2)', borderRadius:20, fontSize:11, color:'var(--text3)' }}>
                  ↔ conversation
                </div>

                {/* Right person */}
                <div style={{ display:'flex', alignItems:'center', gap:6 }}>
                  <Ava user={p2} size={32}/>
                  <div>
                    <div style={{ fontWeight:700, fontSize:13 }}>{p2?.full_name || p2?.username}</div>
                    <div style={{ fontSize:10, color: sendAsId===p2?.id ? 'var(--accent2)' : 'var(--text3)' }}>
                      {sendAsId===p2?.id ? '▶ viewing as this user' : '@'+p2?.username}
                    </div>
                  </div>
                </div>

                <div style={{ marginLeft:'auto', display:'flex', alignItems:'center', gap:8 }}>
                  <span style={{ color:'var(--text3)', fontSize:12 }}>{messages.length} msgs</span>
                  <button className="btn btn-ghost" style={{ padding:'5px 8px' }}
                    onClick={() => loadMessages(selected)}>
                    <RefreshCw size={13}/>
                  </button>
                </div>
              </div>

              {/* Messages area */}
              <div style={{ flex:1, overflowY:'auto', padding:'16px 20px', display:'flex', flexDirection:'column', gap:4 }}>
                {msgLoading ? (
                  <div className="loading"><RefreshCw size={15} style={{ animation:'spin 1s linear infinite' }}/> Loading…</div>
                ) : messages.length === 0 ? (
                  <div className="empty" style={{ flex:1 }}>
                    <MessageSquare size={32}/><p>No messages in this conversation</p>
                  </div>
                ) : (() => {
                  // Group messages by date for date separators
                  let lastDate = ''
                  return messages.map((m, idx) => {
                    // "My" side = the sendAsId user (who admin is acting as)
                    // Right = sent by sendAsId, Left = received from the other
                    const isRight = m.sender_id === sendAsId
                    const sender  = m.sender || (m.sender_id === p1?.id ? p1 : p2)
                    const senderName = sender?.full_name || sender?.username || `User #${m.sender_id}`
                    const senderInitial = (senderName[0] || '?').toUpperCase()

                    // Date separator
                    const msgDate = m.created_at ? new Date(m.created_at).toDateString() : ''
                    const showDate = msgDate && msgDate !== lastDate
                    if (showDate) lastDate = msgDate

                    // Show sender name if different from previous sender
                    const prevSenderId = idx > 0 ? messages[idx-1].sender_id : null
                    const showSenderName = m.sender_id !== prevSenderId

                    const COLS = ['#7c3aed','#ec4899','#3b82f6','#22c55e','#f59e0b','#ef4444']
                    const avatarBg = COLS[(m.sender_id || 0) % COLS.length]
                    const avatarSrc = sender?.profile_image
                      ? (sender.profile_image.startsWith('http') ? sender.profile_image : `/uploads/${sender.profile_image}`)
                      : null

                    return (
                      <React.Fragment key={m.id}>
                        {/* Date separator */}
                        {showDate && (
                          <div style={{ display:'flex', alignItems:'center', gap:10, margin:'12px 0 6px', opacity:0.6 }}>
                            <div style={{ flex:1, height:1, background:'var(--border)' }}/>
                            <span style={{ fontSize:11, color:'var(--text3)', whiteSpace:'nowrap' }}>
                              {new Date(m.created_at).toLocaleDateString([], { weekday:'short', month:'short', day:'numeric' })}
                            </span>
                            <div style={{ flex:1, height:1, background:'var(--border)' }}/>
                          </div>
                        )}

                        {/* Message row */}
                        <div style={{
                          display:'flex',
                          flexDirection: isRight ? 'row-reverse' : 'row',
                          alignItems:'flex-end',
                          gap:8,
                          marginBottom: 2,
                        }}>
                          {/* Avatar — only show if sender changes or first message */}
                          <div style={{ flexShrink:0, width:32 }}>
                            {showSenderName && (
                              avatarSrc
                                ? <img src={avatarSrc} style={{ width:32,height:32,borderRadius:'50%',objectFit:'cover' }} alt=""
                                    onError={e => e.target.style.display='none'}/>
                                : <div style={{
                                    width:32,height:32,borderRadius:'50%',
                                    background:avatarBg,
                                    display:'flex',alignItems:'center',justifyContent:'center',
                                    color:'#fff',fontWeight:700,fontSize:13
                                  }}>
                                    {senderInitial}
                                  </div>
                            )}
                          </div>

                          {/* Bubble + meta */}
                          <div style={{ maxWidth:'65%', display:'flex', flexDirection:'column', alignItems: isRight ? 'flex-end' : 'flex-start' }}>
                            {/* Sender name label */}
                            {showSenderName && (
                              <div style={{
                                fontSize:11, fontWeight:700, marginBottom:3,
                                color: isRight ? 'var(--accent2)' : 'var(--pink)',
                                textAlign: isRight ? 'right' : 'left'
                              }}>
                                {isRight ? '👤 ' : ''}{senderName}
                                {isRight && <span style={{ fontSize:10, fontWeight:400, color:'var(--text3)', marginLeft:4 }}>(you)</span>}
                              </div>
                            )}

                            {/* Bubble */}
                            <div style={{ position:'relative', display:'inline-block' }}>
                              <div style={{
                                background: isRight
                                  ? 'linear-gradient(135deg, #7c3aed, #9333ea)'  /* purple — sent */
                                  : 'var(--surface2)',                             /* grey — received */
                                borderRadius: isRight
                                  ? '18px 4px 18px 18px'
                                  : '4px 18px 18px 18px',
                                padding:'9px 14px',
                                fontSize:13,
                                color: isRight ? '#fff' : 'var(--text)',
                                lineHeight:1.5,
                                border: isRight ? 'none' : '1px solid var(--border)',
                                boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
                                wordBreak: 'break-word',
                              }}>
                                {/* Image preview */}
                                {m.media_url && m.media_type === 'image' && (
                                  <img src={m.media_url} alt=""
                                    style={{ maxWidth:200, maxHeight:180, borderRadius:8, display:'block', marginBottom:6, objectFit:'cover' }}
                                    onError={e => e.target.style.display='none'}
                                  />
                                )}
                                {/* File */}
                                {m.media_url && m.media_type !== 'image' && (
                                  <div style={{ display:'flex', alignItems:'center', gap:6, marginBottom:4,
                                    color: isRight ? 'rgba(255,255,255,0.8)' : 'var(--accent2)', fontSize:12 }}>
                                    <ImgIcon size={14}/> {m.media_url.split('/').pop()?.split('?')[0] || 'File'}
                                  </div>
                                )}
                                {m.content}
                              </div>

                              {/* Delete X button */}
                              <button
                                onClick={() => handleDeleteMsg(m.id)}
                                title="Delete"
                                style={{
                                  position:'absolute', top:-7,
                                  [isRight ? 'left' : 'right']: -7,
                                  width:18, height:18, borderRadius:'50%',
                                  background:'var(--red)', border:'2px solid var(--surface)',
                                  display:'flex', alignItems:'center', justifyContent:'center',
                                  cursor:'pointer', opacity:0, transition:'opacity 0.15s'
                                }}
                                onMouseEnter={e => e.currentTarget.style.opacity='1'}
                                onMouseLeave={e => e.currentTarget.style.opacity='0'}
                              >
                                <X size={9} color="#fff"/>
                              </button>
                            </div>

                            {/* Time + read receipt */}
                            <div style={{
                              fontSize:10, color:'var(--text3)', marginTop:2,
                              display:'flex', gap:4, alignItems:'center',
                              flexDirection: isRight ? 'row-reverse' : 'row'
                            }}>
                              <span>{fmt(m.created_at)}</span>
                              {isRight && m.is_read && <span style={{ color:'var(--blue)' }}>✓✓</span>}
                              {isRight && !m.is_read && <span style={{ color:'var(--text3)' }}>✓</span>}
                            </div>
                          </div>
                        </div>
                      </React.Fragment>
                    )
                  })
                })()}
                <div ref={bottomRef}/>
              </div>

              {/* ── Send message bar ── */}
              <div style={{ padding:'12px 16px', borderTop:'1px solid var(--border)', background:'var(--surface2)' }}>
                {/* Typing indicator */}
                {(() => {
                  const typingUser = [p1, p2].find(u => u && typing[u.id])
                  if (!typingUser) return null
                  return (
                    <div style={{ display:'flex', alignItems:'center', gap:6, marginBottom:8, fontSize:11, color:'var(--text3)' }}>
                      <Ava user={typingUser} size={18}/>
                      <span><b>@{typingUser.username}</b> is typing</span>
                      <span style={{ letterSpacing:2 }}>●●●</span>
                    </div>
                  )
                })()}
                {/* Send-as selector */}
                <div style={{ display:'flex', gap:8, marginBottom:8, alignItems:'center' }}>
                  <span style={{ fontSize:11, color:'var(--text3)', flexShrink:0 }}>Send as:</span>
                  <div style={{ display:'flex', gap:6 }}>
                    {[p1, p2].filter(Boolean).map(u => (
                      <button key={u.id}
                        onClick={() => setSendAsId(u.id)}
                        style={{
                          display:'flex', alignItems:'center', gap:5,
                          padding:'4px 10px', borderRadius:20, border:'none', cursor:'pointer',
                          background: sendAsId===u.id ? 'var(--accent)' : 'var(--surface)',
                          color: sendAsId===u.id ? '#fff' : 'var(--text3)',
                          fontSize:12, fontWeight: sendAsId===u.id ? 600 : 400,
                          transition:'all 0.15s'
                        }}
                      >
                        <Ava user={u} size={18}/>
                        @{u.username}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Input + send button */}
                <div style={{ display:'flex', gap:8, alignItems:'flex-end' }}>
                  <textarea
                    ref={inputRef}
                    value={sendText}
                    onChange={e => setSendText(e.target.value)}
                    onKeyDown={e => {
                      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() }
                    }}
                    placeholder={`Type a message as @${sendAsId===p1?.id ? p1?.username : p2?.username}… (Enter to send)`}
                    rows={2}
                    style={{
                      flex:1, resize:'none', padding:'9px 12px',
                      background:'var(--surface)', border:'1px solid var(--border)',
                      borderRadius:10, color:'var(--text)', fontSize:13,
                      fontFamily:'inherit', lineHeight:1.5, outline:'none'
                    }}
                    onFocus={e => e.target.style.borderColor='var(--accent)'}
                    onBlur={e => e.target.style.borderColor='var(--border)'}
                  />
                  <button
                    className="btn btn-primary"
                    onClick={handleSend}
                    disabled={!sendText.trim() || sending}
                    style={{ padding:'9px 18px', alignSelf:'stretch', minWidth:80 }}
                  >
                    {sending
                      ? <RefreshCw size={15} style={{ animation:'spin 1s linear infinite' }}/>
                      : <><Send size={15}/> Send</>
                    }
                  </button>
                </div>
                <div style={{ fontSize:10, color:'var(--text3)', marginTop:5 }}>
                  Enter to send · Shift+Enter for new line · {connected ? '🟢 Messages delivered in real-time' : '🔴 Reconnecting to live feed…'}
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <style>{`
        @keyframes spin { from{transform:rotate(0)} to{transform:rotate(360deg)} }
      `}</style>
    </div>
  )
}
