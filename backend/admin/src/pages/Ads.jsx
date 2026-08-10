import React, { useState, useEffect } from 'react'
import { adminGetAds, deleteAd, getAdStats } from '../api'
import toast from 'react-hot-toast'
import { Trash2, Eye, RefreshCw, X, TrendingUp, BarChart2, Target, DollarSign, MousePointer } from 'lucide-react'

function AdModal({ ad, onClose }) {
  const [stats, setStats] = useState(null)
  useEffect(() => {
    getAdStats(ad.id).then(d => setStats(d)).catch(() => {})
  }, [ad.id])

  const budget = ad.budget || 0
  const spent = ad.spent || 0
  const pct = budget > 0 ? Math.min(100, (spent / budget) * 100) : 0

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal" style={{ maxWidth:560 }}>
        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:16 }}>
          <span className="modal-title" style={{ marginBottom:0 }}>Ad Details</span>
          <button onClick={onClose} style={{ background:'none', border:'none', color:'var(--text3)', cursor:'pointer' }}><X size={20}/></button>
        </div>
        {ad.media_url && (
          <div style={{ marginBottom:16, borderRadius:10, overflow:'hidden', maxHeight:200, background:'#000', display:'flex', alignItems:'center', justifyContent:'center' }}>
            {ad.media_type === 'image' || !ad.media_type
              ? <img src={ad.media_url} style={{ maxWidth:'100%', maxHeight:200, objectFit:'contain' }} alt=""/>
              : <video src={ad.media_url} controls style={{ maxWidth:'100%', maxHeight:200 }}/>
            }
          </div>
        )}
        <h3 style={{ fontWeight:700, fontSize:16, marginBottom:8 }}>{ad.title}</h3>
        {ad.description && <p style={{ color:'var(--text2)', fontSize:13, marginBottom:16, lineHeight:1.6 }}>{ad.description}</p>}

        {/* Stats grid */}
        <div style={{ display:'grid', gridTemplateColumns:'repeat(4,1fr)', gap:10, marginBottom:20 }}>
          {[
            { label:'Impressions', value:(stats?.impressions || ad.impression_count || 0).toLocaleString(), icon:Eye, color:'var(--blue)' },
            { label:'Clicks', value:(stats?.clicks || ad.click_count || 0).toLocaleString(), icon:MousePointer, color:'var(--green)' },
            { label:'CTR', value:`${(stats?.ctr || 0).toFixed(2)}%`, icon:TrendingUp, color:'var(--yellow)' },
            { label:'Budget', value:`$${budget}`, icon:DollarSign, color:'var(--accent2)' },
          ].map(s => (
            <div key={s.label} style={{ textAlign:'center', background:'var(--surface2)', borderRadius:8, padding:'10px 0' }}>
              <div style={{ color:s.color, fontWeight:700, fontSize:16 }}>{s.value}</div>
              <div style={{ color:'var(--text3)', fontSize:10 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* Budget progress */}
        <div style={{ marginBottom:16 }}>
          <div style={{ display:'flex', justifyContent:'space-between', fontSize:12, marginBottom:6 }}>
            <span style={{ color:'var(--text3)' }}>Budget spent</span>
            <span>${spent} / ${budget}</span>
          </div>
          <div style={{ height:6, background:'var(--surface2)', borderRadius:3 }}>
            <div style={{ height:'100%', width:`${pct}%`, background:'var(--accent)', borderRadius:3, transition:'width 0.3s' }}/>
          </div>
        </div>

        {/* Meta */}
        <div style={{ display:'grid', gap:8, fontSize:13 }}>
          {[
            ['Format', ad.format],
            ['Status', ad.status],
            ['Start', ad.start_date ? new Date(ad.start_date).toLocaleDateString() : '—'],
            ['End', ad.end_date ? new Date(ad.end_date).toLocaleDateString() : '—'],
            ['Target Gender', ad.target_gender],
            ['Target Age', ad.target_age],
            ['Target Interests', ad.target_interests],
          ].filter(([,v]) => v).map(([k, v]) => (
            <div key={k} style={{ display:'flex', gap:12 }}>
              <span style={{ color:'var(--text3)', minWidth:120 }}>{k}</span>
              <span>{v}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export default function Ads() {
  const [ads, setAds] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)

  const load = async () => {
    setLoading(true)
    try {
      const data = await adminGetAds({ page: 1, page_size: 100 })
      setAds(data?.ads || data || [])
    } catch { toast.error('Failed to load ads') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const handleDelete = async (ad) => {
    if (!confirm(`Delete ad "${ad.title}"?`)) return
    try {
      await deleteAd(ad.id)
      setAds(as => as.filter(a => a.id !== ad.id))
      toast.success('Ad deleted')
    } catch { toast.error('Failed to delete ad') }
  }

  const totalImpressions = ads.reduce((a, x) => a + (x.impression_count || 0), 0)
  const totalClicks = ads.reduce((a, x) => a + (x.click_count || 0), 0)
  const totalBudget = ads.reduce((a, x) => a + (x.budget || 0), 0)
  const activeAds = ads.filter(a => a.status === 'active').length

  const statusColor = s => s === 'active' ? 'badge-green' : s === 'paused' ? 'badge-yellow' : 'badge-red'

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Ads & Marketing</div>
          <div className="page-subtitle">{ads.length} total ads • {activeAds} active</div>
        </div>
        <button className="btn btn-ghost" onClick={load}><RefreshCw size={14}/> Refresh</button>
      </div>

      {/* Summary */}
      <div className="stats-grid" style={{ marginBottom:24 }}>
        {[
          { label:'Active Ads', value:activeAds, icon:Target, color:'var(--green)', bg:'rgba(34,197,94,0.15)' },
          { label:'Total Impressions', value:totalImpressions.toLocaleString(), icon:Eye, color:'var(--blue)', bg:'rgba(59,130,246,0.15)' },
          { label:'Total Clicks', value:totalClicks.toLocaleString(), icon:MousePointer, color:'var(--yellow)', bg:'rgba(245,158,11,0.15)' },
          { label:'Total Budget', value:`$${totalBudget.toFixed(0)}`, icon:DollarSign, color:'var(--accent2)', bg:'rgba(124,58,237,0.15)' },
        ].map(s => (
          <div key={s.label} className="stat-card">
            <div className="stat-icon" style={{ background:s.bg }}><s.icon size={20} color={s.color}/></div>
            <div>
              <div className="stat-value" style={{ color:s.color }}>{s.value}</div>
              <div className="stat-label">{s.label}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="card" style={{ padding:0 }}>
        {loading ? <div className="loading"><RefreshCw size={16}/>Loading ads...</div> :
          ads.length === 0 ? (
            <div className="empty" style={{ padding:'40px 0' }}>
              <BarChart2 size={40}/><p>No ads found</p>
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Ad</th>
                  <th>Format</th>
                  <th>Status</th>
                  <th>Performance</th>
                  <th>Budget</th>
                  <th>Targeting</th>
                  <th>Dates</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {ads.map(ad => {
                  const budget = ad.budget || 0
                  const spent = ad.spent || 0
                  const pct = budget > 0 ? Math.min(100, (spent/budget)*100) : 0
                  return (
                    <tr key={ad.id}>
                      <td style={{ maxWidth:200 }}>
                        <div style={{ display:'flex', alignItems:'center', gap:10 }}>
                          {ad.media_url && (
                            <div style={{ width:44, height:36, borderRadius:6, overflow:'hidden', flexShrink:0, background:'var(--surface2)' }}>
                              <img src={ad.media_url} style={{ width:'100%', height:'100%', objectFit:'cover' }} alt=""/>
                            </div>
                          )}
                          <div>
                            <div style={{ fontWeight:600, fontSize:13 }} className="truncate">{ad.title}</div>
                            <div style={{ color:'var(--text3)', fontSize:11 }}>ID #{ad.id}</div>
                          </div>
                        </div>
                      </td>
                      <td><span className="badge badge-blue">{ad.format || 'banner'}</span></td>
                      <td><span className={`badge ${statusColor(ad.status)}`}>{ad.status || 'draft'}</span></td>
                      <td style={{ fontSize:11 }}>
                        <div>👁 {(ad.impression_count||0).toLocaleString()}</div>
                        <div>🖱 {(ad.click_count||0).toLocaleString()}</div>
                        <div style={{ color:'var(--yellow)' }}>CTR: {budget>0 && ad.click_count ? ((ad.click_count/ad.impression_count)*100).toFixed(1) : 0}%</div>
                      </td>
                      <td style={{ fontSize:12 }}>
                        <div style={{ marginBottom:4 }}>${spent} / ${budget}</div>
                        <div style={{ height:4, background:'var(--surface2)', borderRadius:2, width:80 }}>
                          <div style={{ height:'100%', width:`${pct}%`, background:'var(--accent)', borderRadius:2 }}/>
                        </div>
                      </td>
                      <td style={{ fontSize:11, color:'var(--text3)' }}>
                        {ad.target_gender && <div>⚧ {ad.target_gender}</div>}
                        {ad.target_age && <div>🎂 {ad.target_age}</div>}
                      </td>
                      <td style={{ fontSize:11, color:'var(--text3)' }}>
                        <div>{ad.start_date ? new Date(ad.start_date).toLocaleDateString() : '—'}</div>
                        <div>{ad.end_date ? new Date(ad.end_date).toLocaleDateString() : '—'}</div>
                      </td>
                      <td>
                        <div style={{ display:'flex', gap:6 }}>
                          <button className="btn btn-ghost" style={{ padding:'5px 8px' }} onClick={() => setSelected(ad)}>
                            <Eye size={13}/>
                          </button>
                          <button className="btn btn-danger" style={{ padding:'5px 8px' }} onClick={() => handleDelete(ad)}>
                            <Trash2 size={13}/>
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )
        }
      </div>
      {selected && <AdModal ad={selected} onClose={() => setSelected(null)}/>}
    </div>
  )
}
