import React, { useState, useEffect } from 'react'
import { getHealth, getMe } from '../api'
import toast from 'react-hot-toast'
import { Server, User, Shield, Bell, Database, Globe, Save, RefreshCw, CheckCircle, Activity } from 'lucide-react'

function Section({ title, icon: Icon, children }) {
  return (
    <div className="card" style={{ marginBottom:20 }}>
      <div style={{ display:'flex', alignItems:'center', gap:8, marginBottom:20, paddingBottom:14, borderBottom:'1px solid var(--border)' }}>
        <Icon size={18} color="var(--accent2)"/>
        <span style={{ fontWeight:700, fontSize:15 }}>{title}</span>
      </div>
      {children}
    </div>
  )
}

function Row({ label, description, children }) {
  return (
    <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'10px 0', borderBottom:'1px solid var(--border)' }}>
      <div>
        <div style={{ fontSize:13, fontWeight:500 }}>{label}</div>
        {description && <div style={{ fontSize:11, color:'var(--text3)', marginTop:2 }}>{description}</div>}
      </div>
      <div style={{ marginLeft:20 }}>{children}</div>
    </div>
  )
}

function Toggle({ value, onChange }) {
  return (
    <div onClick={() => onChange(!value)}
      style={{
        width:40, height:22, borderRadius:11, cursor:'pointer',
        background: value ? 'var(--accent)' : 'var(--surface2)',
        position:'relative', transition:'background 0.2s',
        border:'1px solid var(--border)'
      }}
    >
      <div style={{
        width:16, height:16, borderRadius:'50%', background:'#fff',
        position:'absolute', top:2, left: value ? 20 : 2,
        transition:'left 0.2s', boxShadow:'0 1px 3px rgba(0,0,0,0.3)'
      }}/>
    </div>
  )
}

export default function Settings() {
  const [health, setHealth] = useState(null)
  const [me, setMe] = useState(null)
  const [settings, setSettings] = useState({
    maintenance: false,
    registrations: true,
    emailVerification: false,
    contentModeration: true,
    autoDeleteReports: false,
    allowGuests: true,
    maxUploadMB: 100,
    jwtExpiry: 7,
    apiRateLimit: 1000,
  })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.allSettled([getHealth(), getMe()]).then(([h, m]) => {
      if (h.status === 'fulfilled') setHealth(h.value)
      if (m.status === 'fulfilled') setMe(m.value?.user || m.value)
      setLoading(false)
    })
  }, [])

  const set = (key, val) => setSettings(s => ({ ...s, [key]: val }))

  const handleSave = () => {
    toast.success('Settings saved (demo — connect to your settings API to persist)')
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Settings</div>
          <div className="page-subtitle">Platform configuration and system info</div>
        </div>
        <button className="btn btn-primary" onClick={handleSave}><Save size={14}/> Save Changes</button>
      </div>

      {/* Server health */}
      <Section title="System Status" icon={Server}>
        {loading ? <div className="loading">Loading...</div> : (
          <div style={{ display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))', gap:12 }}>
            {[
              { label:'API Status', value:health?.status || '—', ok: health?.status === 'ok' },
              { label:'Online Users', value:health?.online_users ?? '—', ok: true },
              { label:'Platform', value:health?.message || 'EnterTok', ok: true },
              { label:'Admin User', value: me ? `@${me.username}` : '—', ok: !!me },
            ].map(item => (
              <div key={item.label} style={{ background:'var(--surface2)', borderRadius:8, padding:'12px 14px', display:'flex', alignItems:'center', gap:10 }}>
                {item.ok ? <CheckCircle size={16} color="var(--green)"/> : <Activity size={16} color="var(--yellow)"/>}
                <div>
                  <div style={{ fontSize:13, fontWeight:600 }}>{item.value}</div>
                  <div style={{ fontSize:11, color:'var(--text3)' }}>{item.label}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </Section>

      {/* Platform settings */}
      <Section title="Platform" icon={Globe}>
        <Row label="Maintenance Mode" description="Disable access for regular users">
          <Toggle value={settings.maintenance} onChange={v => set('maintenance', v)}/>
        </Row>
        <Row label="User Registrations" description="Allow new users to sign up">
          <Toggle value={settings.registrations} onChange={v => set('registrations', v)}/>
        </Row>
        <Row label="Guest Access" description="Allow browsing without account">
          <Toggle value={settings.allowGuests} onChange={v => set('allowGuests', v)}/>
        </Row>
        <Row label="Email Verification" description="Require email verification on signup">
          <Toggle value={settings.emailVerification} onChange={v => set('emailVerification', v)}/>
        </Row>
      </Section>

      {/* Content & Moderation */}
      <Section title="Content & Moderation" icon={Shield}>
        <Row label="Auto Content Moderation" description="Flag inappropriate content automatically">
          <Toggle value={settings.contentModeration} onChange={v => set('contentModeration', v)}/>
        </Row>
        <Row label="Auto-resolve old reports" description="Close reports older than 30 days">
          <Toggle value={settings.autoDeleteReports} onChange={v => set('autoDeleteReports', v)}/>
        </Row>
        <Row label="Max Upload Size (MB)" description="Maximum file upload size per request">
          <input type="number" value={settings.maxUploadMB}
            onChange={e => set('maxUploadMB', Number(e.target.value))}
            style={{ width:80 }} min={1} max={500}/>
        </Row>
      </Section>

      {/* Security */}
      <Section title="Security" icon={Shield}>
        <Row label="JWT Token Expiry (days)" description="How long auth tokens stay valid">
          <input type="number" value={settings.jwtExpiry}
            onChange={e => set('jwtExpiry', Number(e.target.value))}
            style={{ width:80 }} min={1} max={90}/>
        </Row>
        <Row label="API Rate Limit (req/hour)" description="Max requests per user per hour">
          <input type="number" value={settings.apiRateLimit}
            onChange={e => set('apiRateLimit', Number(e.target.value))}
            style={{ width:100 }} min={100} max={10000}/>
        </Row>
      </Section>

      {/* Notifications */}
      <Section title="Notifications" icon={Bell}>
        <Row label="Email Notifications" description="Send emails for important events">
          <Toggle value={true} onChange={() => toast('Connect email provider to enable')}/>
        </Row>
        <Row label="Push Notifications" description="Send push notifications to users">
          <Toggle value={false} onChange={() => toast('Connect FCM/APNS to enable')}/>
        </Row>
      </Section>

      {/* Admin account */}
      <Section title="Admin Account" icon={User}>
        {me ? (
          <div style={{ display:'grid', gap:10, fontSize:13 }}>
            {[
              ['Name', me.full_name || me.username],
              ['Email', me.email],
              ['Role', me.role || 'user'],
              ['ID', `#${me.id}`],
            ].map(([k, v]) => (
              <div key={k} style={{ display:'flex', gap:12, padding:'6px 0', borderBottom:'1px solid var(--border)' }}>
                <span style={{ color:'var(--text3)', minWidth:80 }}>{k}</span>
                <span>{v}</span>
              </div>
            ))}
          </div>
        ) : (
          <div style={{ color:'var(--text3)', fontSize:13 }}>Not logged in</div>
        )}
      </Section>

      {/* API Info */}
      <Section title="API Configuration" icon={Database}>
        <Row label="Backend URL" description="Go API base URL">
          <code style={{ background:'var(--surface2)', padding:'4px 8px', borderRadius:4, fontSize:12 }}>http://192.168.1.7:8082</code>
        </Row>
        <Row label="API Version" description="Current API version">
          <code style={{ background:'var(--surface2)', padding:'4px 8px', borderRadius:4, fontSize:12 }}>/api/v1</code>
        </Row>
        <Row label="WebSocket" description="Real-time connection endpoint">
          <code style={{ background:'var(--surface2)', padding:'4px 8px', borderRadius:4, fontSize:12 }}>ws://192.168.1.7:8082/ws</code>
        </Row>
        <Row label="Database" description="Database engine">
          <span className="badge badge-green">SQLite</span>
        </Row>
      </Section>
    </div>
  )
}
