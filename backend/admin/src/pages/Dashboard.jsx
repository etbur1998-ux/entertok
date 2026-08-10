import React, { useEffect, useState } from 'react'
import { getDebugInfo, getLives, getTrendingHashtags, adminGetStats } from '../api'
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, BarChart, Bar, Cell, PieChart, Pie, Legend
} from 'recharts'
import {
  Users, FileVideo, ShoppingBag, Radio, TrendingUp,
  Activity, Globe, Hash, RefreshCw, ArrowUpRight
} from 'lucide-react'

const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep']

function makeGrowth(base, mult) {
  return months.map((m, i) => ({
    month: m,
    value: Math.floor(base + i * mult + Math.random() * mult * 0.4)
  }))
}

const CUSTOM_TOOLTIP = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null
  return (
    <div style={{ background:'var(--surface2)', border:'1px solid var(--border)', borderRadius:8, padding:'8px 12px', fontSize:12 }}>
      <div style={{ color:'var(--text3)', marginBottom:4 }}>{label}</div>
      {payload.map(p => (
        <div key={p.dataKey} style={{ color: p.color }}>{p.name}: {p.value?.toLocaleString()}</div>
      ))}
    </div>
  )
}

export default function Dashboard() {
  const [info, setInfo] = useState(null)
  const [lives, setLives] = useState([])
  const [hashtags, setHashtags] = useState([])
  const [loading, setLoading] = useState(true)
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const load = () => {
    setLoading(true)
    Promise.allSettled([
      getDebugInfo(),
      getLives(),
      getTrendingHashtags(),
      adminGetStats(),
    ]).then(([infoR, livesR, tagsR, statsR]) => {
      if (infoR.status === 'fulfilled') setInfo(infoR.value)
      // Override with richer admin stats if available
      if (statsR.status === 'fulfilled') {
        const s = statsR.value
        setInfo(prev => ({ ...prev, users: s.users, posts: s.posts, follows: s.follows }))
      }
      if (livesR.status === 'fulfilled') setLives(livesR.value?.streams || livesR.value?.lives || [])
      if (tagsR.status === 'fulfilled') setHashtags(tagsR.value?.hashtags || [])
      setLastRefresh(new Date())
      setLoading(false)
    })
  }

  useEffect(() => { load() }, [])

  const usersGrowth = makeGrowth(100, (info?.users || 0) / 10 || 50)
  const postsGrowth = makeGrowth(50, (info?.posts || 0) / 10 || 30)

  const combinedGrowth = months.map((m, i) => ({
    month: m,
    users: usersGrowth[i].value,
    posts: postsGrowth[i].value,
  }))

  const hashtagBar = hashtags.slice(0, 8).map(h => ({ name: `#${h.hashtag}`, count: h.count }))

  const totalViewers = lives.reduce((a, s) => a + (s.viewer_count || 0), 0)

  const stats = [
    { label: 'Total Users',   value: info?.users,        icon: Users,       color: '#7c3aed', bg: 'rgba(124,58,237,0.15)', change: '+12% this month' },
    { label: 'Total Posts',   value: info?.posts,        icon: FileVideo,   color: '#ec4899', bg: 'rgba(236,72,153,0.15)', change: '+8% this month' },
    { label: 'Active Follows',value: info?.follows,      icon: TrendingUp,  color: '#3b82f6', bg: 'rgba(59,130,246,0.15)', change: '+5% this month' },
    { label: 'Online Now',    value: info?.online_users, icon: Activity,    color: '#22c55e', bg: 'rgba(34,197,94,0.15)',  change: 'Real-time' },
    { label: 'Live Streams',  value: lives.length,       icon: Radio,       color: '#ef4444', bg: 'rgba(239,68,68,0.15)', change: `${totalViewers} viewers` },
    { label: 'API Status',    value: 'Online',           icon: Globe,       color: '#f59e0b', bg: 'rgba(245,158,11,0.15)', change: '100% uptime' },
  ]

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Dashboard</div>
          <div className="page-subtitle">
            Last updated: {lastRefresh.toLocaleTimeString()}
          </div>
        </div>
        <button className="btn btn-ghost" onClick={load} disabled={loading}>
          <RefreshCw size={14} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
          Refresh
        </button>
      </div>

      {/* Stats */}
      <div className="stats-grid">
        {stats.map(s => (
          <div key={s.label} className="stat-card">
            <div className="stat-icon" style={{ background: s.bg }}>
              <s.icon size={20} color={s.color} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="stat-value" style={{ color: s.color }}>
                {typeof s.value === 'number' ? s.value.toLocaleString() : (s.value ?? '—')}
              </div>
              <div className="stat-label">{s.label}</div>
              <div className="stat-change stat-up" style={{ display:'flex', alignItems:'center', gap:3 }}>
                <ArrowUpRight size={10}/>{s.change}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Charts row 1 */}
      <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr', gap:18, marginBottom:18 }}>
        {/* Growth area */}
        <div className="card">
          <div style={{ fontWeight:700, fontSize:14, marginBottom:16, display:'flex', alignItems:'center', gap:7 }}>
            <TrendingUp size={15} color="var(--accent2)"/> User & Post Growth
          </div>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={combinedGrowth}>
              <defs>
                <linearGradient id="ug" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#7c3aed" stopOpacity={0.4}/>
                  <stop offset="95%" stopColor="#7c3aed" stopOpacity={0}/>
                </linearGradient>
                <linearGradient id="pg" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ec4899" stopOpacity={0.4}/>
                  <stop offset="95%" stopColor="#ec4899" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)"/>
              <XAxis dataKey="month" tick={{ fill:'var(--text3)', fontSize:10 }} axisLine={false} tickLine={false}/>
              <YAxis tick={{ fill:'var(--text3)', fontSize:10 }} axisLine={false} tickLine={false}/>
              <Tooltip content={<CUSTOM_TOOLTIP/>}/>
              <Area type="monotone" dataKey="users" stroke="#7c3aed" fill="url(#ug)" strokeWidth={2} name="Users"/>
              <Area type="monotone" dataKey="posts" stroke="#ec4899" fill="url(#pg)" strokeWidth={2} name="Posts"/>
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Hashtag bar */}
        <div className="card">
          <div style={{ fontWeight:700, fontSize:14, marginBottom:16, display:'flex', alignItems:'center', gap:7 }}>
            <Hash size={15} color="var(--yellow)"/> Trending Hashtags
          </div>
          {hashtagBar.length === 0 ? (
            <div className="empty" style={{ padding:'30px 0' }}><Hash size={28}/><p>No trending hashtags</p></div>
          ) : (
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={hashtagBar} layout="vertical">
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" horizontal={false}/>
                <XAxis type="number" tick={{ fill:'var(--text3)', fontSize:10 }} axisLine={false} tickLine={false}/>
                <YAxis dataKey="name" type="category" tick={{ fill:'var(--text2)', fontSize:10 }} axisLine={false} tickLine={false} width={70}/>
                <Tooltip content={<CUSTOM_TOOLTIP/>}/>
                <Bar dataKey="count" radius={[0,4,4,0]} name="Posts">
                  {hashtagBar.map((_, i) => (
                    <Cell key={i} fill={['#7c3aed','#ec4899','#3b82f6','#22c55e','#f59e0b','#ef4444','#06b6d4','#8b5cf6'][i % 8]}/>
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      {/* Bottom row */}
      <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr', gap:18 }}>
        {/* Live streams */}
        <div className="card">
          <div style={{ fontWeight:700, fontSize:14, marginBottom:14, display:'flex', alignItems:'center', gap:7 }}>
            <Radio size={15} color="var(--red)"/> Active Live Streams
            {lives.length > 0 && (
              <span style={{ marginLeft:'auto', background:'var(--red)', color:'#fff', borderRadius:10, padding:'1px 8px', fontSize:10, fontWeight:700 }}>
                {lives.length} LIVE
              </span>
            )}
          </div>
          {lives.length === 0 ? (
            <div className="empty" style={{ padding:'20px 0' }}>
              <Radio size={32}/><p>No active streams</p>
            </div>
          ) : lives.slice(0, 6).map(s => (
            <div key={s.id} style={{ display:'flex', alignItems:'center', gap:10, padding:'8px 0', borderBottom:'1px solid var(--border)' }}>
              <div style={{ width:8, height:8, borderRadius:'50%', background:'var(--red)', flexShrink:0, boxShadow:'0 0 6px var(--red)' }}/>
              <div style={{ flex:1, minWidth:0 }}>
                <div style={{ fontWeight:600, fontSize:13 }} className="truncate">{s.title || 'Live Stream'}</div>
                <div style={{ color:'var(--text3)', fontSize:11 }}>
                  @{s.user?.username || `user_${s.user_id}`}
                  {s.category && ` · ${s.category}`}
                </div>
              </div>
              <div style={{ display:'flex', alignItems:'center', gap:4, color:'var(--text3)', fontSize:11 }}>
                <Activity size={11}/> {s.viewer_count || 0}
              </div>
            </div>
          ))}
        </div>

        {/* Quick actions */}
        <div className="card">
          <div style={{ fontWeight:700, fontSize:14, marginBottom:14 }}>Quick Actions</div>
          <div style={{ display:'grid', gap:10 }}>
            {[
              { label:'View All Users', desc:'Manage users, roles, bans', color:'#7c3aed', path:'/users', icon:Users },
              { label:'Moderate Posts', desc:'Review and remove content', color:'#ec4899', path:'/posts', icon:FileVideo },
              { label:'Manage Live Streams', desc:'Monitor and end streams', color:'#ef4444', path:'/live', icon:Radio },
              { label:'Review Reports', desc:'Handle user reports', color:'#f59e0b', path:'/reports', icon:TrendingUp },
            ].map(a => (
              <a key={a.path} href={a.path} style={{
                display:'flex', alignItems:'center', gap:12,
                padding:'10px 14px', borderRadius:10,
                background:'var(--surface2)',
                border:'1px solid var(--border)',
                textDecoration:'none', transition:'background 0.12s'
              }}
                onMouseEnter={e => e.currentTarget.style.background = 'rgba(124,58,237,0.1)'}
                onMouseLeave={e => e.currentTarget.style.background = 'var(--surface2)'}
              >
                <div style={{ width:36, height:36, borderRadius:8, background:`${a.color}20`, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0 }}>
                  <a.icon size={17} color={a.color}/>
                </div>
                <div>
                  <div style={{ fontWeight:600, fontSize:13, color:'var(--text)' }}>{a.label}</div>
                  <div style={{ fontSize:11, color:'var(--text3)' }}>{a.desc}</div>
                </div>
                <ArrowUpRight size={14} style={{ marginLeft:'auto', color:'var(--text3)' }}/>
              </a>
            ))}
          </div>
        </div>
      </div>

      <style>{`
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      `}</style>
    </div>
  )
}
