import React, { useState, useEffect, useCallback, useRef } from 'react'
import { adminGetUsers, adminBanUser, adminUnbanUser, adminVerifyUser, getUserPosts, getFollowers, getFollowing } from '../api'
import toast from 'react-hot-toast'
import {
  Search, Eye, RefreshCw, X, Users as UsersIcon,
  FileVideo, Ban, CheckCircle, ShieldCheck, ChevronLeft, ChevronRight
} from 'lucide-react'

// ── Avatar ────────────────────────────────────────────────────────────────────
function Avatar({ user, size = 36 }) {
  const COLORS = ['#7c3aed','#ec4899','#3b82f6','#22c55e','#f59e0b','#ef4444']
  const bg = COLORS[(user?.id || 0) % COLORS.length]
  const src = user?.profile_image
    ? (user.profile_image.startsWith('http') ? user.profile_image : `/uploads/${user.profile_image}`)
    : null
  if (src) return <img src={src} style={{ width:size,height:size,borderRadius:'50%',objectFit:'cover',flexShrink:0 }} alt="" onError={e => { e.target.style.display='none' }}/>
  return (
    <div style={{ width:size,height:size,borderRadius:'50%',background:bg,display:'flex',alignItems:'center',justifyContent:'center',color:'#fff',fontWeight:700,fontSize:size*0.38,flexShrink:0 }}>
      {((user?.full_name || user?.username || 'U')[0]).toUpperCase()}
    </div>
  )
}

// ── User Detail Modal ─────────────────────────────────────────────────────────
function UserModal({ user, onClose, onBan, onVerify }) {
  const [posts, setPosts]       = useState([])
  const [followers, setFollowers] = useState([])
  const [following, setFollowing] = useState([])
  const [tab, setTab]           = useState('info')
  const [loading, setLoading]   = useState(true)

  useEffect(() => {
    if (!user) return
    setLoading(true)
    Promise.allSettled([
      getUserPosts(user.id),
      getFollowers(user.id),
      getFollowing(user.id),
    ]).then(([p, f1, f2]) => {
      setPosts(p.status==='fulfilled' ? (p.value?.posts||[]) : [])
      setFollowers(f1.status==='fulfilled' ? (f1.value?.followers||f1.value||[]) : [])
      setFollowing(f2.status==='fulfilled' ? (f2.value?.following||f2.value||[]) : [])
      setLoading(false)
    })
  }, [user])

  if (!user) return null
  const isBanned = user.role === 'banned'

  return (
    <div className="modal-overlay" onClick={e => e.target===e.currentTarget && onClose()}>
      <div className="modal" style={{ maxWidth:640 }}>
        {/* Header */}
        <div style={{ display:'flex',alignItems:'center',gap:14,marginBottom:20 }}>
          <Avatar user={user} size={60}/>
          <div style={{ flex:1 }}>
            <div style={{ fontWeight:700,fontSize:19 }}>{user.full_name||user.username}</div>
            <div style={{ color:'var(--text3)',fontSize:13 }}>@{user.username} · ID #{user.id}</div>
            <div style={{ display:'flex',gap:6,marginTop:6,flexWrap:'wrap' }}>
              <span className={`badge ${user.is_online?'badge-green':'badge-red'}`}>{user.is_online?'● Online':'○ Offline'}</span>
              <span className={`badge ${user.is_verified?'badge-blue':'badge-yellow'}`}>{user.is_verified?'✓ Verified':'Unverified'}</span>
              <span className={`badge ${isBanned?'badge-red':user.role==='admin'?'badge-purple':'badge-blue'}`}>{user.role||'user'}</span>
              {user.gender && <span className="badge badge-pink">{user.gender}</span>}
            </div>
          </div>
          <button onClick={onClose} style={{ background:'none',border:'none',color:'var(--text3)',cursor:'pointer' }}><X size={20}/></button>
        </div>

        {/* Stats */}
        <div style={{ display:'grid',gridTemplateColumns:'repeat(4,1fr)',gap:10,marginBottom:18 }}>
          {[['Posts',user.post_count||0],['Followers',user.follower_count||0],['Following',user.following_count||0],['ID',user.id]].map(([l,v])=>(
            <div key={l} style={{ textAlign:'center',background:'var(--surface2)',borderRadius:8,padding:'10px 0' }}>
              <div style={{ fontWeight:700,fontSize:18,color:'var(--accent2)' }}>{typeof v==='number'?v.toLocaleString():v}</div>
              <div style={{ color:'var(--text3)',fontSize:11 }}>{l}</div>
            </div>
          ))}
        </div>

        {/* Tabs */}
        <div style={{ display:'flex',gap:3,marginBottom:14,background:'var(--surface2)',borderRadius:8,padding:3 }}>
          {['info','posts','followers','following'].map(t=>(
            <button key={t} onClick={()=>setTab(t)} style={{ flex:1,padding:'6px 0',borderRadius:6,border:'none',background:tab===t?'var(--accent)':'transparent',color:tab===t?'#fff':'var(--text3)',fontSize:12,fontWeight:600,cursor:'pointer',textTransform:'capitalize' }}>{t}</button>
          ))}
        </div>

        <div style={{ maxHeight:260,overflowY:'auto' }}>
          {loading && tab!=='info' ? <div className="loading">Loading...</div> : (
            <>
              {tab==='info' && (
                <div style={{ display:'grid',gap:9 }}>
                  {[
                    ['Email',user.email],['Bio',user.bio],['Location',user.location],
                    ['Website',user.website],['Gender',user.gender],
                    ['Joined',user.created_at?new Date(user.created_at).toLocaleDateString():'—'],
                  ].filter(([,v])=>v).map(([k,v])=>(
                    <div key={k} style={{ display:'flex',gap:12,fontSize:13 }}>
                      <span style={{ color:'var(--text3)',minWidth:80 }}>{k}</span>
                      <span style={{ wordBreak:'break-all' }}>{v}</span>
                    </div>
                  ))}
                </div>
              )}
              {tab==='posts' && (
                posts.length===0 ? <div className="empty"><FileVideo size={28}/><p>No posts</p></div> :
                posts.map(p=>(
                  <div key={p.id} style={{ display:'flex',gap:10,padding:'8px 0',borderBottom:'1px solid var(--border)',alignItems:'center' }}>
                    <div style={{ width:52,height:40,background:'var(--surface2)',borderRadius:6,flexShrink:0,overflow:'hidden',display:'flex',alignItems:'center',justifyContent:'center' }}>
                      {p.media_type==='image'&&p.media_url?<img src={p.media_url} style={{ width:'100%',height:'100%',objectFit:'cover' }} alt=""/>:<span style={{ fontSize:18 }}>🎬</span>}
                    </div>
                    <div style={{ flex:1,minWidth:0 }}>
                      <div style={{ fontSize:12,marginBottom:2 }} className="truncate">{p.content||'(no caption)'}</div>
                      <div style={{ fontSize:11,color:'var(--text3)' }}>❤ {p.like_count||0} · 💬 {p.comment_count||0} · 👁 {p.view_count||0}</div>
                    </div>
                  </div>
                ))
              )}
              {tab==='followers' && (
                followers.length===0 ? <div className="empty"><UsersIcon size={28}/><p>No followers</p></div> :
                followers.map(u=>(
                  <div key={u.id} style={{ display:'flex',alignItems:'center',gap:10,padding:'6px 0',borderBottom:'1px solid var(--border)' }}>
                    <Avatar user={u} size={30}/>
                    <div><div style={{ fontSize:13,fontWeight:600 }}>{u.full_name||u.username}</div><div style={{ fontSize:11,color:'var(--text3)' }}>@{u.username}</div></div>
                  </div>
                ))
              )}
              {tab==='following' && (
                following.length===0 ? <div className="empty"><UsersIcon size={28}/><p>Not following anyone</p></div> :
                following.map(u=>(
                  <div key={u.id} style={{ display:'flex',alignItems:'center',gap:10,padding:'6px 0',borderBottom:'1px solid var(--border)' }}>
                    <Avatar user={u} size={30}/>
                    <div><div style={{ fontSize:13,fontWeight:600 }}>{u.full_name||u.username}</div><div style={{ fontSize:11,color:'var(--text3)' }}>@{u.username}</div></div>
                  </div>
                ))
              )}
            </>
          )}
        </div>

        {/* Actions */}
        <div style={{ display:'flex',gap:8,marginTop:18,justifyContent:'flex-end',flexWrap:'wrap' }}>
          {!user.is_verified && (
            <button className="btn btn-success" onClick={()=>{ onVerify(user); onClose() }}><ShieldCheck size={14}/> Verify</button>
          )}
          {isBanned
            ? <button className="btn btn-ghost" onClick={()=>{ onBan(user,'unban'); onClose() }}><CheckCircle size={14}/> Unban</button>
            : user.role !== 'admin' && <button className="btn btn-danger" onClick={()=>{ onBan(user,'ban'); onClose() }}><Ban size={14}/> Ban User</button>
          }
          <button className="btn btn-ghost" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  )
}

// ── Main Users page ────────────────────────────────────────────────────────────
export default function Users() {
  const [users, setUsers]   = useState([])
  const [total, setTotal]   = useState(0)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [page, setPage]     = useState(1)
  const [selected, setSelected] = useState(null)
  const PER = 20
  const wsRef = useRef(null)

  const load = useCallback(async (q='', pg=1) => {
    setLoading(true)
    try {
      const data = await adminGetUsers({ q, page: pg, page_size: PER })
      setUsers(data?.users || [])
      setTotal(data?.total || 0)
    } catch(e) {
      const msg = e?.error || e?.message || JSON.stringify(e) || 'Check backend is running on :8080'
      toast.error('Failed to load users: ' + msg)
      console.error('adminGetUsers error:', e)
    } finally {
      setLoading(false)
    }
  }, [])

  // Initial load
  useEffect(() => { load('', 1) }, [load])

  // Debounced search
  useEffect(() => {
    const t = setTimeout(() => { setPage(1); load(search, 1) }, 350)
    return () => clearTimeout(t)
  }, [search, load])

  // Real-time online status via WebSocket
  useEffect(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) return
    try {
      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws?token=${token}`);
      wsRef.current = ws
      ws.onmessage = e => {
        try {
          const msg = JSON.parse(e.data)
          if (msg.type === 'online_status' && msg.payload) {
            setUsers(prev => prev.map(u =>
              u.id === msg.payload.user_id ? { ...u, is_online: msg.payload.is_online } : u
            ))
          }
        } catch {}
      }
      return () => ws.close()
    } catch {}
  }, [])

  const handleBan = async (user, action) => {
    try {
      if (action === 'ban') await adminBanUser(user.id)
      else await adminUnbanUser(user.id)
      toast.success(`User ${action === 'ban' ? 'banned' : 'unbanned'}`)
      setUsers(prev => prev.map(u => u.id===user.id ? { ...u, role: action==='ban'?'banned':'user' } : u))
    } catch { toast.error('Action failed') }
  }

  const handleVerify = async (user) => {
    try {
      await adminVerifyUser(user.id)
      toast.success('User verified ✓')
      setUsers(prev => prev.map(u => u.id===user.id ? { ...u, is_verified: true } : u))
    } catch { toast.error('Failed to verify') }
  }

  const totalPages = Math.ceil(total / PER)
  const onlineCnt  = users.filter(u => u.is_online).length
  const bannedCnt  = users.filter(u => u.role === 'banned').length

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Users</div>
          <div className="page-subtitle">
            {total.toLocaleString()} total · {onlineCnt} online now · {bannedCnt} banned
          </div>
        </div>
        <div style={{ display:'flex',gap:8 }}>
          <div className="search-bar" style={{ minWidth:300 }}>
            <Search size={14}/>
            <input type="search" placeholder="Search by name, username or email…"
              value={search} onChange={e=>{ setSearch(e.target.value) }}/>
          </div>
          <button className="btn btn-ghost" onClick={()=>load(search,page)}>
            <RefreshCw size={14}/> Refresh
          </button>
        </div>
      </div>

      {/* Summary cards */}
      <div className="stats-grid" style={{ marginBottom:20 }}>
        {[
          { label:'Total Users',    value:total,     color:'var(--accent2)', bg:'rgba(124,58,237,0.15)' },
          { label:'Online Now',     value:onlineCnt, color:'var(--green)',   bg:'rgba(34,197,94,0.15)' },
          { label:'Banned',         value:bannedCnt, color:'var(--red)',     bg:'rgba(239,68,68,0.15)' },
          { label:'Showing',        value:users.length, color:'var(--blue)', bg:'rgba(59,130,246,0.15)' },
        ].map(s=>(
          <div key={s.label} className="stat-card">
            <div style={{ flex:1 }}>
              <div className="stat-value" style={{ color:s.color,fontSize:22 }}>{s.value?.toLocaleString()}</div>
              <div className="stat-label">{s.label}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="card" style={{ padding:0,overflow:'hidden' }}>
        {loading ? (
          <div className="loading"><RefreshCw size={16} style={{ animation:'spin 1s linear infinite' }}/> Loading users…</div>
        ) : users.length === 0 ? (
          <div className="empty" style={{ padding:'50px 0' }}>
            <UsersIcon size={48}/><p>No users found</p>
            {search && <p style={{ fontSize:13 }}>Try a different search term</p>}
          </div>
        ) : (
          <>
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>User</th>
                  <th>Email</th>
                  <th>Gender</th>
                  <th>Stats</th>
                  <th>Status</th>
                  <th>Role</th>
                  <th>Joined</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {users.map(u => {
                  const isBanned = u.role === 'banned'
                  return (
                    <tr key={u.id} style={{ opacity: isBanned ? 0.6 : 1 }}>
                      <td style={{ color:'var(--text3)',fontSize:12 }}>#{u.id}</td>
                      <td>
                        <div style={{ display:'flex',alignItems:'center',gap:10 }}>
                          <div style={{ position:'relative' }}>
                            <Avatar user={u} size={36}/>
                            {u.is_online && <div style={{ position:'absolute',bottom:0,right:0,width:9,height:9,borderRadius:'50%',background:'var(--green)',border:'2px solid var(--surface)' }}/>}
                          </div>
                          <div>
                            <div style={{ fontWeight:600,fontSize:13,display:'flex',alignItems:'center',gap:5 }}>
                              {u.full_name||u.username}
                              {u.is_verified && <span title="Verified" style={{ color:'var(--blue)',fontSize:11 }}>✓</span>}
                            </div>
                            <div style={{ color:'var(--text3)',fontSize:11 }}>@{u.username}</div>
                          </div>
                        </div>
                      </td>
                      <td style={{ fontSize:12,maxWidth:170 }}>
                        <div className="truncate">{u.email||'—'}</div>
                      </td>
                      <td>
                        {u.gender
                          ? <span className={`badge ${u.gender.toLowerCase()==='female'?'badge-pink':'badge-blue'}`}>{u.gender}</span>
                          : <span style={{ color:'var(--text3)' }}>—</span>}
                      </td>
                      <td style={{ fontSize:11,color:'var(--text3)',whiteSpace:'nowrap' }}>
                        <div>📝 {(u.post_count||0).toLocaleString()}</div>
                        <div>👥 {(u.follower_count||0).toLocaleString()}</div>
                      </td>
                      <td>
                        <div style={{ display:'flex',flexDirection:'column',gap:4 }}>
                          <span className={`badge ${u.is_online?'badge-green':'badge-red'}`} style={{ fontSize:10 }}>
                            {u.is_online?'● Online':'○ Offline'}
                          </span>
                          {u.is_private && <span className="badge badge-yellow" style={{ fontSize:10 }}>🔒 Private</span>}
                        </div>
                      </td>
                      <td>
                        <span className={`badge ${isBanned?'badge-red':u.role==='admin'?'badge-purple':'badge-blue'}`}>
                          {u.role||'user'}
                        </span>
                      </td>
                      <td style={{ fontSize:11,color:'var(--text3)',whiteSpace:'nowrap' }}>
                        {u.created_at?new Date(u.created_at).toLocaleDateString():'—'}
                      </td>
                      <td>
                        <div style={{ display:'flex',gap:5 }}>
                          <button className="btn btn-ghost" style={{ padding:'5px 8px',fontSize:11 }} onClick={()=>setSelected(u)}>
                            <Eye size={12}/> View
                          </button>
                          {!u.is_verified && (
                            <button className="btn btn-success" style={{ padding:'5px 8px' }} title="Verify" onClick={()=>handleVerify(u)}>
                              <ShieldCheck size={12}/>
                            </button>
                          )}
                          {u.role!=='admin' && (
                            isBanned
                              ? <button className="btn btn-ghost" style={{ padding:'5px 8px' }} title="Unban" onClick={()=>handleBan(u,'unban')}><CheckCircle size={12}/></button>
                              : <button className="btn btn-danger" style={{ padding:'5px 8px' }} title="Ban" onClick={()=>handleBan(u,'ban')}><Ban size={12}/></button>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>

            {/* Pagination */}
            {totalPages > 1 && (
              <div style={{ display:'flex',alignItems:'center',gap:8,padding:'12px 16px',borderTop:'1px solid var(--border)',justifyContent:'space-between' }}>
                <span style={{ color:'var(--text3)',fontSize:12 }}>
                  Page {page} of {totalPages} · {total} users
                </span>
                <div style={{ display:'flex',gap:6 }}>
                  <button className="btn btn-ghost" disabled={page===1} onClick={()=>{ setPage(p=>p-1); load(search,page-1) }} style={{ padding:'5px 10px' }}>
                    <ChevronLeft size={14}/> Prev
                  </button>
                  {Array.from({ length: Math.min(5,totalPages) }, (_,i) => {
                    const pg = Math.max(1, Math.min(page-2,totalPages-4)) + i
                    return (
                      <button key={pg} onClick={()=>{ setPage(pg); load(search,pg) }}
                        style={{ padding:'5px 10px',border:'none',cursor:'pointer',borderRadius:6,background:pg===page?'var(--accent)':'var(--surface2)',color:pg===page?'#fff':'var(--text2)',fontSize:12 }}>
                        {pg}
                      </button>
                    )
                  })}
                  <button className="btn btn-ghost" disabled={page===totalPages} onClick={()=>{ setPage(p=>p+1); load(search,page+1) }} style={{ padding:'5px 10px' }}>
                    Next <ChevronRight size={14}/>
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {selected && <UserModal user={selected} onClose={()=>setSelected(null)} onBan={handleBan} onVerify={handleVerify}/>}

      <style>{`@keyframes spin { from{transform:rotate(0deg)} to{transform:rotate(360deg)} }`}</style>
    </div>
  )
}
