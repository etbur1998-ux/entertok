import React, { useState, useEffect, useCallback } from 'react'
import api from '../api'
import toast from 'react-hot-toast'
import {
  Rocket, RefreshCw, StopCircle, Eye, X, TrendingUp,
  DollarSign, Users, Gift, BarChart2, CheckCircle, Clock
} from 'lucide-react'

// ── helpers ───────────────────────────────────────────────────────────────────
const fmt2 = n => (typeof n === 'number' ? n.toFixed(2) : '0.00')
const fmtN = n => (typeof n === 'number' ? n.toLocaleString() : '0')

function ProgressBar({ pct, color = 'var(--accent)' }) {
  return (
    <div style={{ height: 8, background: 'var(--surface2)', borderRadius: 4, overflow: 'hidden', minWidth: 80 }}>
      <div style={{
        height: '100%', width: `${Math.min(100, pct || 0)}%`,
        background: color, borderRadius: 4, transition: 'width 0.4s'
      }} />
    </div>
  )
}

function CampaignModal({ campaign: c, onClose, onStop }) {
  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal" style={{ maxWidth: 540 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
          <span style={{ fontWeight: 700, fontSize: 16 }}>Campaign #{c.id}</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--text3)', cursor: 'pointer' }}>
            <X size={20} />
          </button>
        </div>

        {/* User */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 18, padding: '12px 14px', background: 'var(--surface2)', borderRadius: 10 }}>
          {c.profile_image
            ? <img src={c.profile_image} style={{ width: 42, height: 42, borderRadius: '50%', objectFit: 'cover' }} alt="" />
            : <div style={{ width: 42, height: 42, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 700 }}>
                {(c.username || 'U')[0].toUpperCase()}
              </div>
          }
          <div>
            <div style={{ fontWeight: 700, fontSize: 15 }}>{c.full_name || c.username}</div>
            <div style={{ color: 'var(--text3)', fontSize: 12 }}>@{c.username} · User #{c.user_id}</div>
          </div>
          <span className={`badge ${c.status === 'active' ? 'badge-green' : c.status === 'completed' ? 'badge-blue' : c.status === 'cancelled' ? 'badge-red' : 'badge-yellow'}`} style={{ marginLeft: 'auto' }}>
            {c.status?.toUpperCase()}
          </span>
        </div>

        {/* Stats grid */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 10, marginBottom: 18 }}>
          {[
            { label: 'Target', value: fmtN(c.target_followers), color: 'var(--blue)' },
            { label: 'Gained', value: fmtN(c.followers_gained), color: 'var(--green)' },
            { label: 'Progress', value: `${fmt2(c.progress_pct)}%`, color: 'var(--accent2)' },
            { label: 'Total Cost', value: `${fmt2(c.total_cost)} Birr`, color: 'var(--yellow)' },
            { label: 'Spent', value: `${fmt2(c.total_spent)} Birr`, color: 'var(--pink)' },
            { label: 'Platform Revenue', value: `${fmt2(c.platform_revenue)} Birr`, color: 'var(--green)' },
          ].map(s => (
            <div key={s.label} style={{ textAlign: 'center', background: 'var(--surface2)', borderRadius: 8, padding: '10px 0' }}>
              <div style={{ fontWeight: 700, fontSize: 16, color: s.color }}>{s.value}</div>
              <div style={{ color: 'var(--text3)', fontSize: 10 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* Progress bar */}
        <div style={{ marginBottom: 18 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, marginBottom: 6 }}>
            <span style={{ color: 'var(--text3)' }}>Progress</span>
            <span>{c.followers_gained} / {c.target_followers} followers</span>
          </div>
          <ProgressBar pct={c.progress_pct} />
        </div>

        {/* Pricing */}
        <div style={{ background: 'var(--surface2)', borderRadius: 10, padding: '12px 14px', marginBottom: 18 }}>
          <div style={{ fontWeight: 600, marginBottom: 10, fontSize: 13 }}>Pricing Structure</div>
          {[
            ['Buyer pays', `${fmt2(c.price_per_follower)} Birr / follower`],
            ['Follower earns', `${fmt2(c.earn_per_follower)} Birr / follow`],
            ['Platform fee', `${fmt2(c.fee_per_follower)} Birr / follow`],
          ].map(([k, v]) => (
            <div key={k} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, padding: '4px 0', borderBottom: '1px solid var(--border)' }}>
              <span style={{ color: 'var(--text3)' }}>{k}</span>
              <span style={{ fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>

        {/* Created at */}
        <div style={{ color: 'var(--text3)', fontSize: 12, marginBottom: 16 }}>
          Created: {c.created_at ? new Date(c.created_at).toLocaleString() : '—'}
        </div>

        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          <button className="btn btn-ghost" onClick={onClose}>Close</button>
          {c.status === 'active' && (
            <button className="btn btn-danger" onClick={() => { onStop(c.id); onClose() }}>
              <StopCircle size={14} /> Force Stop
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Main Boosts page ──────────────────────────────────────────────────────────
export default function Boosts() {
  const [campaigns, setCampaigns] = useState([])
  const [rewards, setRewards]     = useState([])
  const [stats, setStats]         = useState(null)
  const [loading, setLoading]     = useState(true)
  const [tab, setTab]             = useState('campaigns') // campaigns | rewards
  const [filter, setFilter]       = useState('all')
  const [selected, setSelected]   = useState(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [boostData, rewardData] = await Promise.all([
        api.get('/admin/boosts', { params: { status: filter === 'all' ? '' : filter, page: 1, page_size: 100 } }),
        api.get('/admin/boosts/rewards', { params: { page: 1, page_size: 100 } }),
      ])
      setCampaigns(boostData?.campaigns || [])
      setStats(boostData?.platform_stats || null)
      setRewards(rewardData?.rewards || [])
    } catch (e) {
      toast.error('Failed to load: ' + (e?.error || e?.message || 'Unknown'))
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => { load() }, [load])

  const handleStop = async (id) => {
    if (!confirm('Force stop this campaign?')) return
    try {
      await api.post(`/admin/boosts/${id}/stop`)
      toast.success('Campaign stopped')
      load()
    } catch { toast.error('Failed to stop') }
  }

  const statusColor = s =>
    s === 'active' ? 'badge-green' : s === 'completed' ? 'badge-blue' :
    s === 'cancelled' ? 'badge-red' : 'badge-yellow'

  const activeCnt    = campaigns.filter(c => c.status === 'active').length
  const completedCnt = campaigns.filter(c => c.status === 'completed').length

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Boost Campaigns</div>
          <div className="page-subtitle">
            {campaigns.length} campaigns · {activeCnt} active · {completedCnt} completed
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <select value={filter} onChange={e => setFilter(e.target.value)} style={{ width: 'auto' }}>
            <option value="all">All Status</option>
            <option value="active">Active</option>
            <option value="completed">Completed</option>
            <option value="paused">Paused</option>
            <option value="cancelled">Cancelled</option>
          </select>
          <button className="btn btn-ghost" onClick={load}><RefreshCw size={14} /> Refresh</button>
        </div>
      </div>

      {/* ── Pricing info banner ── */}
      <div style={{
        background: 'linear-gradient(135deg, rgba(124,58,237,0.15), rgba(236,72,153,0.15))',
        border: '1px solid rgba(124,58,237,0.3)', borderRadius: 'var(--radius)',
        padding: '14px 20px', marginBottom: 20,
        display: 'flex', gap: 32, alignItems: 'center', flexWrap: 'wrap'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Rocket size={18} color="var(--accent2)" />
          <span style={{ fontWeight: 700, fontSize: 15 }}>Boost Pricing</span>
        </div>
        {[
          { label: 'Buyer pays', value: '2.00 Birr / follower', color: 'var(--yellow)' },
          { label: 'Follower earns', value: '1.70 Birr / follow', color: 'var(--green)' },
          { label: 'Platform fee', value: '0.30 Birr / follow', color: 'var(--accent2)' },
        ].map(p => (
          <div key={p.label} style={{ fontSize: 13 }}>
            <span style={{ color: 'var(--text3)' }}>{p.label}: </span>
            <span style={{ fontWeight: 700, color: p.color }}>{p.value}</span>
          </div>
        ))}
      </div>

      {/* ── Platform stats ── */}
      {stats && (
        <div className="stats-grid" style={{ marginBottom: 20 }}>
          {[
            { label: 'Platform Revenue', value: `${fmt2(stats.total_revenue)} Birr`, icon: DollarSign, color: 'var(--green)',   bg: 'rgba(34,197,94,0.15)' },
            { label: 'Total Paid Out', value: `${fmt2(stats.total_paid_out)} Birr`,  icon: Gift,        color: 'var(--pink)',    bg: 'rgba(236,72,153,0.15)' },
            { label: 'Total Rewards',   value: fmtN(stats.total_rewards),             icon: Users,       color: 'var(--blue)',    bg: 'rgba(59,130,246,0.15)' },
            { label: 'Active Campaigns',value: fmtN(activeCnt),                       icon: TrendingUp,  color: 'var(--accent2)', bg: 'rgba(124,58,237,0.15)' },
          ].map(s => (
            <div key={s.label} className="stat-card">
              <div className="stat-icon" style={{ background: s.bg }}>
                <s.icon size={20} color={s.color} />
              </div>
              <div>
                <div className="stat-value" style={{ color: s.color }}>{s.value}</div>
                <div className="stat-label">{s.label}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── Tab switcher ── */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 16, background: 'var(--surface2)', borderRadius: 8, padding: 4, width: 'fit-content' }}>
        {[['campaigns', 'Campaigns'], ['rewards', 'Reward Payments']].map(([key, label]) => (
          <button key={key} onClick={() => setTab(key)} style={{
            padding: '7px 20px', borderRadius: 6, border: 'none', cursor: 'pointer',
            background: tab === key ? 'var(--accent)' : 'transparent',
            color: tab === key ? '#fff' : 'var(--text3)',
            fontWeight: tab === key ? 700 : 400, fontSize: 13
          }}>{label}</button>
        ))}
      </div>

      {/* ── Campaigns table ── */}
      {tab === 'campaigns' && (
        <div className="card" style={{ padding: 0 }}>
          {loading ? (
            <div className="loading"><RefreshCw size={16} style={{ animation: 'spin 1s linear infinite' }} /> Loading...</div>
          ) : campaigns.length === 0 ? (
            <div className="empty" style={{ padding: '50px 0' }}>
              <Rocket size={48} /><p>No boost campaigns yet</p>
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>#ID</th>
                  <th>User</th>
                  <th>Target / Gained</th>
                  <th>Progress</th>
                  <th>Cost / Spent</th>
                  <th>Platform Rev.</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {campaigns.map(c => (
                  <tr key={c.id}>
                    <td style={{ color: 'var(--text3)', fontSize: 12 }}>#{c.id}</td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        {c.profile_image
                          ? <img src={c.profile_image} style={{ width: 30, height: 30, borderRadius: '50%', objectFit: 'cover' }} alt="" />
                          : <div style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 12, fontWeight: 700 }}>
                              {(c.username || 'U')[0].toUpperCase()}
                            </div>
                        }
                        <div>
                          <div style={{ fontWeight: 600, fontSize: 13 }}>{c.full_name || c.username}</div>
                          <div style={{ color: 'var(--text3)', fontSize: 11 }}>@{c.username}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ fontSize: 13 }}>
                      <span style={{ color: 'var(--green)', fontWeight: 700 }}>{c.followers_gained}</span>
                      <span style={{ color: 'var(--text3)' }}> / {c.target_followers}</span>
                    </td>
                    <td style={{ minWidth: 120 }}>
                      <div style={{ marginBottom: 4, fontSize: 11, color: 'var(--text3)' }}>{fmt2(c.progress_pct)}%</div>
                      <ProgressBar pct={c.progress_pct}
                        color={c.status === 'completed' ? 'var(--blue)' : c.status === 'cancelled' ? 'var(--red)' : 'var(--accent)'}
                      />
                    </td>
                    <td style={{ fontSize: 12 }}>
                      <div style={{ color: 'var(--text3)' }}>{fmt2(c.total_spent)} / {fmt2(c.total_cost)}</div>
                      <div style={{ fontSize: 10, color: 'var(--text3)' }}>Birr</div>
                    </td>
                    <td style={{ fontWeight: 700, color: 'var(--green)', fontSize: 13 }}>
                      {fmt2(c.platform_revenue)} Birr
                    </td>
                    <td>
                      <span className={`badge ${statusColor(c.status)}`}>{c.status || 'unknown'}</span>
                    </td>
                    <td style={{ fontSize: 11, color: 'var(--text3)', whiteSpace: 'nowrap' }}>
                      {c.created_at ? new Date(c.created_at).toLocaleDateString() : '—'}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 5 }}>
                        <button className="btn btn-ghost" style={{ padding: '5px 8px' }} onClick={() => setSelected(c)}>
                          <Eye size={13} />
                        </button>
                        {c.status === 'active' && (
                          <button className="btn btn-danger" style={{ padding: '5px 8px' }} onClick={() => handleStop(c.id)}>
                            <StopCircle size={13} />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* ── Rewards table ── */}
      {tab === 'rewards' && (
        <div className="card" style={{ padding: 0 }}>
          {loading ? (
            <div className="loading"><RefreshCw size={16} style={{ animation: 'spin 1s linear infinite' }} /> Loading...</div>
          ) : rewards.length === 0 ? (
            <div className="empty" style={{ padding: '50px 0' }}>
              <Gift size={48} /><p>No reward payments yet</p>
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Follower (Earned)</th>
                  <th>Followed (Boosted)</th>
                  <th>Earned</th>
                  <th>Platform Fee</th>
                  <th>Status</th>
                  <th>Paid At</th>
                </tr>
              </thead>
              <tbody>
                {rewards.map(r => (
                  <tr key={r.id}>
                    <td style={{ color: 'var(--text3)', fontSize: 12 }}>#{r.id}</td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        {r.follower?.profile_image
                          ? <img src={r.follower.profile_image} style={{ width: 28, height: 28, borderRadius: '50%', objectFit: 'cover' }} alt="" />
                          : <div style={{ width: 28, height: 28, borderRadius: '50%', background: 'var(--green)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 11, fontWeight: 700 }}>
                              {(r.follower?.username || 'U')[0].toUpperCase()}
                            </div>
                        }
                        <div>
                          <div style={{ fontWeight: 600, fontSize: 12 }}>@{r.follower?.username}</div>
                          <div style={{ color: 'var(--green)', fontSize: 11 }}>+{fmt2(r.earn_amount)} Birr</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        {r.boosted_user?.profile_image
                          ? <img src={r.boosted_user.profile_image} style={{ width: 28, height: 28, borderRadius: '50%', objectFit: 'cover' }} alt="" />
                          : <div style={{ width: 28, height: 28, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 11, fontWeight: 700 }}>
                              {(r.boosted_user?.username || 'U')[0].toUpperCase()}
                            </div>
                        }
                        <span style={{ fontSize: 12 }}>@{r.boosted_user?.username}</span>
                      </div>
                    </td>
                    <td style={{ fontWeight: 700, color: 'var(--green)', fontSize: 13 }}>
                      {fmt2(r.earn_amount)} Birr
                    </td>
                    <td style={{ fontWeight: 700, color: 'var(--accent2)', fontSize: 13 }}>
                      {fmt2(r.fee_amount)} Birr
                    </td>
                    <td>
                      <span className={`badge ${r.status === 'paid' ? 'badge-green' : 'badge-yellow'}`}>
                        {r.status === 'paid' ? <CheckCircle size={10} /> : <Clock size={10} />}
                        {' '}{r.status}
                      </span>
                    </td>
                    <td style={{ fontSize: 11, color: 'var(--text3)', whiteSpace: 'nowrap' }}>
                      {r.paid_at ? new Date(r.paid_at).toLocaleString() : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {selected && <CampaignModal campaign={selected} onClose={() => setSelected(null)} onStop={handleStop} />}
      <style>{`@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}`}</style>
    </div>
  )
}
