import React, { useState, useEffect } from 'react'
import { getLives, endLiveStream } from '../api'
import toast from 'react-hot-toast'
import { Radio, Eye, Users, StopCircle, RefreshCw, X, Gift } from 'lucide-react'

function LiveModal({ stream: s, onClose, onEnd }) {
  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:16 }}>
          <span className="modal-title" style={{ marginBottom:0 }}>Live Stream Details</span>
          <button onClick={onClose} style={{ background:'none', border:'none', color:'var(--text3)', cursor:'pointer' }}><X size={20}/></button>
        </div>
        {s.thumbnail_url && (
          <img src={s.thumbnail_url} alt="thumbnail"
            style={{ width:'100%', height:200, objectFit:'cover', borderRadius:10, marginBottom:16 }}/>
        )}
        <div style={{ display:'grid', gap:10, fontSize:13 }}>
          <h3 style={{ fontSize:17, fontWeight:700 }}>{s.title || 'Untitled Stream'}</h3>
          {s.description && <p style={{ color:'var(--text2)', lineHeight:1.6 }}>{s.description}</p>}
          {[
            ['Stream ID', `#${s.id}`],
            ['Broadcaster', s.user?.username ? `@${s.user.username}` : `User #${s.user_id}`],
            ['Viewers', `${s.viewer_count || 0}`],
            ['Category', s.category],
            ['Started', s.started_at ? new Date(s.started_at).toLocaleString() : '—'],
            ['Status', s.is_active ? 'Active' : 'Ended'],
          ].map(([k, v]) => v ? (
            <div key={k} style={{ display:'flex', gap:12 }}>
              <span style={{ color:'var(--text3)', minWidth:100 }}>{k}</span>
              <span>{v}</span>
            </div>
          ) : null)}
        </div>
        {s.is_active && (
          <div style={{ marginTop:20, display:'flex', gap:8, justifyContent:'flex-end' }}>
            <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
            <button className="btn btn-danger" onClick={() => { onEnd(s); onClose() }}>
              <StopCircle size={14}/> Force End Stream
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

export default function LiveStreams() {
  const [streams, setStreams] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)

  const load = async () => {
    setLoading(true)
    try {
      const data = await getLives()
      setStreams(data?.streams || data?.lives || [])
    } catch { toast.error('Failed to load streams') }
    finally { setLoading(false) }
  }

  useEffect(() => { load(); const t = setInterval(load, 30000); return () => clearInterval(t) }, [])

  const handleEnd = async (s) => {
    if (!confirm(`Force end "${s.title || 'stream'}"?`)) return
    try {
      await endLiveStream(s.id)
      setStreams(ss => ss.filter(x => x.id !== s.id))
      toast.success('Stream ended')
    } catch { toast.error('Failed to end stream') }
  }

  const totalViewers = streams.reduce((a, s) => a + (s.viewer_count || 0), 0)

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Live Streams</div>
          <div className="page-subtitle">{streams.length} active • {totalViewers} total viewers</div>
        </div>
        <div style={{ display:'flex', gap:8 }}>
          <span className="badge badge-red"><span style={{ width:7,height:7,borderRadius:'50%',background:'var(--red)',display:'inline-block',marginRight:4 }}></span>Auto-refreshes every 30s</span>
          <button className="btn btn-ghost" onClick={load}><RefreshCw size={14}/> Refresh</button>
        </div>
      </div>

      {/* Summary cards */}
      <div className="stats-grid" style={{ marginBottom:24 }}>
        {[
          { label:'Active Streams', value:streams.length, icon:Radio, color:'var(--red)', bg:'rgba(239,68,68,0.15)' },
          { label:'Total Viewers', value:totalViewers, icon:Eye, color:'var(--blue)', bg:'rgba(59,130,246,0.15)' },
          { label:'Unique Broadcasters', value:[...new Set(streams.map(s=>s.user_id))].length, icon:Users, color:'var(--green)', bg:'rgba(34,197,94,0.15)' },
        ].map(s => (
          <div key={s.label} className="stat-card">
            <div className="stat-icon" style={{ background:s.bg }}>
              <s.icon size={20} color={s.color}/>
            </div>
            <div>
              <div className="stat-value" style={{ color:s.color }}>{s.value}</div>
              <div className="stat-label">{s.label}</div>
            </div>
          </div>
        ))}
      </div>

      {loading ? (
        <div className="loading"><RefreshCw size={16}/> Loading streams...</div>
      ) : streams.length === 0 ? (
        <div className="empty card">
          <Radio size={48}/><p style={{ fontSize:16 }}>No active live streams</p>
          <p style={{ fontSize:13 }}>Streams will appear here in real-time</p>
        </div>
      ) : (
        <div style={{ display:'grid', gridTemplateColumns:'repeat(auto-fill,minmax(280px,1fr))', gap:16 }}>
          {streams.map(s => (
            <div key={s.id} className="card" style={{ padding:0, overflow:'hidden' }}>
              {/* Thumbnail / header */}
              <div style={{ height:140, background:'linear-gradient(135deg,#1a0f2e,#2d1b69)', position:'relative', display:'flex', alignItems:'center', justifyContent:'center' }}>
                {s.thumbnail_url
                  ? <img src={s.thumbnail_url} style={{ width:'100%',height:'100%',objectFit:'cover' }} alt=""/>
                  : <Radio size={40} color="rgba(255,255,255,0.3)"/>
                }
                {/* LIVE badge */}
                <div style={{ position:'absolute', top:10, left:10, display:'flex', alignItems:'center', gap:5, background:'var(--red)', padding:'4px 10px', borderRadius:20 }}>
                  <span style={{ width:7,height:7,borderRadius:'50%',background:'#fff',animation:'pulse 1s infinite' }}></span>
                  <span style={{ color:'#fff', fontWeight:700, fontSize:12 }}>LIVE</span>
                </div>
                {/* Viewer count */}
                <div style={{ position:'absolute', top:10, right:10, display:'flex', alignItems:'center', gap:4, background:'rgba(0,0,0,0.6)', padding:'4px 10px', borderRadius:20 }}>
                  <Eye size={12} color="#fff"/>
                  <span style={{ color:'#fff', fontSize:12 }}>{s.viewer_count || 0}</span>
                </div>
              </div>
              <div style={{ padding:'12px 14px' }}>
                <div style={{ fontWeight:700, fontSize:14, marginBottom:4 }} className="truncate">{s.title || 'Untitled Stream'}</div>
                <div style={{ color:'var(--text3)', fontSize:12, marginBottom:8 }}>
                  {s.user?.full_name || s.user?.username || `User #${s.user_id}`}
                  {s.category && <span className="badge badge-purple" style={{ marginLeft:6 }}>{s.category}</span>}
                </div>
                <div style={{ color:'var(--text3)', fontSize:11, marginBottom:12 }}>
                  Started: {s.started_at ? new Date(s.started_at).toLocaleTimeString() : '—'}
                </div>
                <div style={{ display:'flex', gap:6 }}>
                  <button className="btn btn-ghost" style={{ flex:1, justifyContent:'center', fontSize:12 }} onClick={() => setSelected(s)}>
                    <Eye size={13}/> Details
                  </button>
                  <button className="btn btn-danger" style={{ padding:'7px 12px', fontSize:12 }} onClick={() => handleEnd(s)}>
                    <StopCircle size={13}/> End
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
      {selected && <LiveModal stream={selected} onClose={() => setSelected(null)} onEnd={handleEnd}/>}
    </div>
  )
}
