import React, { useState, useEffect } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, Users, FileVideo, ShoppingBag,
  Radio, Megaphone, MessageSquare, Flag, Settings,
  LogOut, ChevronLeft, ChevronRight, Clapperboard,
  Activity, Rocket
} from 'lucide-react'
import { getDebugInfo, getLives } from '../api'

const NAV = [
  { to: '/',         icon: LayoutDashboard, label: 'Dashboard',      end: true },
  { to: '/users',    icon: Users,           label: 'Users' },
  { to: '/posts',    icon: FileVideo,       label: 'Posts & Videos' },
  { to: '/products', icon: ShoppingBag,     label: 'Marketplace' },
  { to: '/live',     icon: Radio,           label: 'Live Streams',   badge: 'live' },
  { to: '/boosts',   icon: Rocket,          label: 'Boost Campaigns' },
  { to: '/ads',      icon: Megaphone,       label: 'Ads' },
  { to: '/messages', icon: MessageSquare,   label: 'Messages' },
  { to: '/reports',  icon: Flag,            label: 'Reports' },
  { to: '/settings', icon: Settings,        label: 'Settings' },
]

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const [info, setInfo] = useState(null)
  const [liveCount, setLiveCount] = useState(0)
  const navigate = useNavigate()

  useEffect(() => {
    getDebugInfo().then(setInfo).catch(() => {})
    getLives().then(d => setLiveCount((d?.streams || d?.lives || []).length)).catch(() => {})
    const t = setInterval(() => {
      getLives().then(d => setLiveCount((d?.streams || d?.lives || []).length)).catch(() => {})
    }, 30000)
    return () => clearInterval(t)
  }, [])

  const handleLogout = () => {
    localStorage.removeItem('admin_token')
    navigate('/login')
  }

  const getBadge = (key) => {
    if (key === 'live') return liveCount > 0 ? liveCount : null
    return null
  }

  return (
    <div style={{ display:'flex', minHeight:'100vh' }}>
      {/* ── Sidebar ── */}
      <aside style={{
        width: collapsed ? 60 : 220,
        background: 'var(--surface)',
        borderRight: '1px solid var(--border)',
        display: 'flex', flexDirection: 'column',
        transition: 'width 0.2s ease',
        flexShrink: 0,
        position: 'sticky', top: 0, height: '100vh',
        overflow: 'hidden'
      }}>
        {/* Logo */}
        <div style={{
          padding: collapsed ? '18px 0' : '18px 14px',
          display: 'flex', alignItems: 'center', gap: 10,
          borderBottom: '1px solid var(--border)',
          justifyContent: collapsed ? 'center' : 'flex-start'
        }}>
          <div style={{
            width: 32, height: 32, borderRadius: 8, flexShrink: 0,
            background: 'linear-gradient(135deg, var(--accent), var(--pink))',
            display: 'flex', alignItems: 'center', justifyContent: 'center'
          }}>
            <Clapperboard size={17} color="#fff" />
          </div>
          {!collapsed && (
            <div>
              <div style={{ fontWeight: 800, fontSize: 14, color: 'var(--text)', lineHeight: 1 }}>EnterTok</div>
              <div style={{ fontSize: 10, color: 'var(--text3)' }}>Admin Panel</div>
            </div>
          )}
        </div>

        {/* Online indicator */}
        {!collapsed && info && (
          <div style={{ padding: '8px 14px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--green)' }} />
            <span style={{ fontSize: 11, color: 'var(--text3)' }}>{info.online_users ?? 0} online now</span>
          </div>
        )}

        {/* Nav links */}
        <nav style={{ flex: 1, padding: '8px 0', overflowY: 'auto' }}>
          {NAV.map(({ to, icon: Icon, label, end, badge }) => {
            const badgeVal = badge ? getBadge(badge) : null
            return (
              <NavLink
                key={to} to={to} end={end}
                style={({ isActive }) => ({
                  display: 'flex', alignItems: 'center',
                  gap: 9,
                  padding: collapsed ? '9px 0' : '9px 14px',
                  justifyContent: collapsed ? 'center' : 'flex-start',
                  color: isActive ? '#fff' : 'var(--text3)',
                  background: isActive ? 'rgba(124,58,237,0.18)' : 'transparent',
                  borderRight: isActive ? '3px solid var(--accent)' : '3px solid transparent',
                  fontSize: 13, fontWeight: isActive ? 600 : 400,
                  textDecoration: 'none', transition: 'all 0.12s',
                  position: 'relative'
                })}
              >
                <Icon size={17} strokeWidth={1.8} />
                {!collapsed && <span style={{ flex: 1 }}>{label}</span>}
                {!collapsed && badgeVal && (
                  <span style={{
                    background: 'var(--red)', color: '#fff',
                    borderRadius: 10, padding: '1px 6px', fontSize: 10, fontWeight: 700
                  }}>{badgeVal}</span>
                )}
                {collapsed && badgeVal && (
                  <span style={{
                    position: 'absolute', top: 6, right: 6,
                    width: 8, height: 8, borderRadius: '50%', background: 'var(--red)'
                  }} />
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* Logout */}
        <div style={{ borderTop: '1px solid var(--border)', padding: '8px 0' }}>
          <button onClick={handleLogout} style={{
            display: 'flex', alignItems: 'center', gap: 9,
            padding: collapsed ? '9px 0' : '9px 14px',
            justifyContent: collapsed ? 'center' : 'flex-start',
            width: '100%', background: 'none', border: 'none',
            color: 'var(--red)', fontSize: 13, cursor: 'pointer'
          }}>
            <LogOut size={17} />
            {!collapsed && <span>Logout</span>}
          </button>
        </div>

        {/* Collapse toggle */}
        <button onClick={() => setCollapsed(c => !c)} style={{
          position: 'absolute', right: -11, top: '50%', transform: 'translateY(-50%)',
          width: 22, height: 22, borderRadius: '50%',
          background: 'var(--surface2)', border: '1px solid var(--border)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer', zIndex: 10, flexShrink: 0
        }}>
          {collapsed ? <ChevronRight size={11} /> : <ChevronLeft size={11} />}
        </button>
      </aside>

      {/* ── Main area ── */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* Topbar */}
        <header style={{
          height: 54, background: 'var(--surface)',
          borderBottom: '1px solid var(--border)',
          display: 'flex', alignItems: 'center',
          padding: '0 22px', gap: 14, flexShrink: 0
        }}>
          {info && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, fontSize: 12, color: 'var(--text3)' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <Users size={12} /> {info.users ?? '—'} users
              </span>
              <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <FileVideo size={12} /> {info.posts ?? '—'} posts
              </span>
              <span style={{ display: 'flex', alignItems: 'center', gap: 4, color: liveCount > 0 ? 'var(--red)' : 'var(--text3)' }}>
                <Radio size={12} /> {liveCount} live
              </span>
            </div>
          )}
          <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 11, color: 'var(--green)' }}>
              <Activity size={12} /> API Online
            </div>
            <div style={{
              width: 32, height: 32, borderRadius: '50%',
              background: 'linear-gradient(135deg, var(--accent), var(--pink))',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontWeight: 700, fontSize: 13, color: '#fff'
            }}>A</div>
          </div>
        </header>

        {/* Page */}
        <main style={{ flex: 1, overflowY: 'auto', padding: 22 }}>
          <Outlet />
        </main>
      </div>
    </div>
  )
}
