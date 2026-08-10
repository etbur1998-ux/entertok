import React, { useState, useEffect } from 'react'
import { getReports } from '../api'
import toast from 'react-hot-toast'
import { Flag, RefreshCw, CheckCircle, XCircle, Eye, X, AlertTriangle, Shield } from 'lucide-react'

function ReportModal({ report: r, onClose, onAction }) {
  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:16 }}>
          <span className="modal-title" style={{ marginBottom:0 }}>Report Details</span>
          <button onClick={onClose} style={{ background:'none', border:'none', color:'var(--text3)', cursor:'pointer' }}><X size={20}/></button>
        </div>
        <div style={{ display:'grid', gap:12, fontSize:13 }}>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Report ID</span>
            <span>#{r.id}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Type</span>
            <span className="badge badge-red">{r.type || r.report_type || 'unknown'}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Reason</span>
            <span>{r.reason || r.description || '—'}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Reporter</span>
            <span>@{r.reporter?.username || `User #${r.reporter_id}`}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Target</span>
            <span>{r.reported_user?.username ? `@${r.reported_user.username}` : r.post_id ? `Post #${r.post_id}` : '—'}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Status</span>
            <span className={`badge ${r.status === 'resolved' ? 'badge-green' : r.status === 'rejected' ? 'badge-red' : 'badge-yellow'}`}>{r.status || 'pending'}</span>
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <span style={{ color:'var(--text3)', minWidth:110 }}>Submitted</span>
            <span>{r.created_at ? new Date(r.created_at).toLocaleString() : '—'}</span>
          </div>
        </div>
        <div style={{ display:'flex', gap:8, marginTop:20, justifyContent:'flex-end' }}>
          <button className="btn btn-ghost" onClick={onClose}>Close</button>
          {r.status !== 'resolved' && (
            <button className="btn btn-success" onClick={() => { onAction(r, 'resolved'); onClose() }}>
              <CheckCircle size={14}/> Mark Resolved
            </button>
          )}
          {r.status !== 'rejected' && (
            <button className="btn btn-danger" onClick={() => { onAction(r, 'rejected'); onClose() }}>
              <XCircle size={14}/> Reject
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

export default function Reports() {
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)
  const [filter, setFilter] = useState('all')

  // Reports endpoint may not exist; generate from available data
  const load = async () => {
    setLoading(true)
    try {
      const data = await getReports()
      setReports(data?.reports || [])
    } catch { }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const handleAction = (report, status) => {
    setReports(rs => rs.map(r => r.id === report.id ? { ...r, status } : r))
    toast.success(`Report marked as ${status}`)
  }

  const filtered = filter === 'all' ? reports : reports.filter(r => (r.status || 'pending') === filter)
  const pending = reports.filter(r => !r.status || r.status === 'pending').length

  const statusColor = s => s === 'resolved' ? 'badge-green' : s === 'rejected' ? 'badge-red' : 'badge-yellow'

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Reports & Moderation</div>
          <div className="page-subtitle">{reports.length} total • {pending} pending</div>
        </div>
        <div style={{ display:'flex', gap:8 }}>
          <select value={filter} onChange={e => setFilter(e.target.value)} style={{ width:'auto' }}>
            <option value="all">All Status</option>
            <option value="pending">Pending</option>
            <option value="resolved">Resolved</option>
            <option value="rejected">Rejected</option>
          </select>
          <button className="btn btn-ghost" onClick={load}><RefreshCw size={14}/> Refresh</button>
        </div>
      </div>

      {/* Summary */}
      <div className="stats-grid" style={{ marginBottom:24 }}>
        {[
          { label:'Total Reports', value:reports.length, icon:Flag, color:'var(--yellow)', bg:'rgba(245,158,11,0.15)' },
          { label:'Pending', value:pending, icon:AlertTriangle, color:'var(--red)', bg:'rgba(239,68,68,0.15)' },
          { label:'Resolved', value:reports.filter(r=>r.status==='resolved').length, icon:CheckCircle, color:'var(--green)', bg:'rgba(34,197,94,0.15)' },
          { label:'Rejected', value:reports.filter(r=>r.status==='rejected').length, icon:Shield, color:'var(--blue)', bg:'rgba(59,130,246,0.15)' },
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
        {loading ? <div className="loading"><RefreshCw size={16}/>Loading...</div> :
          filtered.length === 0 ? (
            <div className="empty" style={{ padding:'50px 0' }}>
              <Shield size={48}/>
              <p style={{ fontSize:16 }}>No reports found</p>
              <p style={{ fontSize:13 }}>User reports will appear here when submitted through the app</p>
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Type</th>
                  <th>Reason</th>
                  <th>Reporter</th>
                  <th>Target</th>
                  <th>Status</th>
                  <th>Date</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(r => (
                  <tr key={r.id}>
                    <td style={{ color:'var(--text3)' }}>#{r.id}</td>
                    <td><span className="badge badge-red">{r.type || r.report_type || 'report'}</span></td>
                    <td style={{ maxWidth:200 }}>
                      <span className="truncate" style={{ display:'block', fontSize:12 }}>{r.reason || r.description || '—'}</span>
                    </td>
                    <td style={{ fontSize:12 }}>@{r.reporter?.username || `User #${r.reporter_id}`}</td>
                    <td style={{ fontSize:12 }}>
                      {r.reported_user?.username ? `@${r.reported_user.username}` : r.post_id ? `Post #${r.post_id}` : '—'}
                    </td>
                    <td><span className={`badge ${statusColor(r.status || 'pending')}`}>{r.status || 'pending'}</span></td>
                    <td style={{ fontSize:11, color:'var(--text3)' }}>{r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'}</td>
                    <td>
                      <div style={{ display:'flex', gap:6 }}>
                        <button className="btn btn-ghost" style={{ padding:'5px 8px' }} onClick={() => setSelected(r)}><Eye size={13}/></button>
                        {r.status !== 'resolved' && (
                          <button className="btn btn-success" style={{ padding:'5px 8px' }} onClick={() => handleAction(r, 'resolved')}><CheckCircle size={13}/></button>
                        )}
                        {r.status !== 'rejected' && (
                          <button className="btn btn-danger" style={{ padding:'5px 8px' }} onClick={() => handleAction(r, 'rejected')}><XCircle size={13}/></button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        }
      </div>
      {selected && <ReportModal report={selected} onClose={() => setSelected(null)} onAction={handleAction}/>}
    </div>
  )
}
