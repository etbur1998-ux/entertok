import React, { useState, useEffect, useCallback } from 'react'
import { adminGetPosts, adminDeletePost, getComments } from '../api'
import toast from 'react-hot-toast'
import {
  Trash2, Eye, RefreshCw, X, MessageCircle, Heart,
  Play, Image as Img, FileText, ChevronLeft, ChevronRight, Search
} from 'lucide-react'

function PostModal({ post, onClose, onDelete }) {
  const [comments, setComments] = useState([])
  const [loading, setLoading]   = useState(true)

  useEffect(() => {
    getComments(post.id)
      .then(d => setComments(d?.comments || []))
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [post.id])

  return (
    <div className="modal-overlay" onClick={e => e.target===e.currentTarget && onClose()}>
      <div className="modal" style={{ maxWidth:620 }}>
        <div style={{ display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:16 }}>
          <span style={{ fontWeight:700,fontSize:17 }}>Post #{post.id}</span>
          <button onClick={onClose} style={{ background:'none',border:'none',color:'var(--text3)',cursor:'pointer' }}><X size={20}/></button>
        </div>

        {/* Media */}
        {post.media_url && (
          <div style={{ marginBottom:16,borderRadius:10,overflow:'hidden',maxHeight:300,background:'#000',display:'flex',alignItems:'center',justifyContent:'center' }}>
            {post.media_type==='image'
              ? <img src={post.media_url} style={{ maxWidth:'100%',maxHeight:300,objectFit:'contain' }} alt=""/>
              : <video src={post.media_url} controls style={{ maxWidth:'100%',maxHeight:300 }}/>
            }
          </div>
        )}

        {post.content && <p style={{ marginBottom:16,lineHeight:1.6,fontSize:14 }}>{post.content}</p>}

        {/* Stats */}
        <div style={{ display:'grid',gridTemplateColumns:'repeat(4,1fr)',gap:10,marginBottom:18 }}>
          {[
            { label:'Likes',    value:post.like_count||0,    color:'var(--pink)' },
            { label:'Comments', value:post.comment_count||0, color:'var(--blue)' },
            { label:'Views',    value:post.view_count||0,    color:'var(--accent2)' },
            { label:'Shares',   value:post.share_count||0,   color:'var(--green)' },
          ].map(s=>(
            <div key={s.label} style={{ textAlign:'center',background:'var(--surface2)',borderRadius:8,padding:'10px 0' }}>
              <div style={{ color:s.color,fontWeight:700,fontSize:17 }}>{s.value.toLocaleString()}</div>
              <div style={{ color:'var(--text3)',fontSize:11 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* Meta */}
        <div style={{ display:'grid',gap:8,fontSize:13,marginBottom:16 }}>
          {[
            ['Author', post.user?.full_name||post.user?.username||`User #${post.user_id}`],
            ['Posted', post.created_at?new Date(post.created_at).toLocaleString():'—'],
            ['Type',   post.media_type||'text'],
          ].map(([k,v])=>(
            <div key={k} style={{ display:'flex',gap:12 }}>
              <span style={{ color:'var(--text3)',minWidth:70 }}>{k}</span>
              <span>{v}</span>
            </div>
          ))}
          {post.hashtags && (
            <div style={{ display:'flex',gap:6,flexWrap:'wrap' }}>
              {(Array.isArray(post.hashtags)?post.hashtags:post.hashtags.split(',')).filter(Boolean).map(h=>(
                <span key={h} className="badge badge-purple">#{h.trim()}</span>
              ))}
            </div>
          )}
        </div>

        {/* Comments */}
        <div style={{ fontWeight:600,marginBottom:10,fontSize:13 }}>Comments ({comments.length})</div>
        <div style={{ maxHeight:200,overflowY:'auto' }}>
          {loading ? <div style={{ color:'var(--text3)',fontSize:13 }}>Loading…</div> :
            comments.length===0 ? <div style={{ color:'var(--text3)',fontSize:13 }}>No comments</div> :
            comments.map(c=>(
              <div key={c.id} style={{ display:'flex',gap:8,fontSize:12,padding:'6px 0',borderBottom:'1px solid var(--border)' }}>
                <span style={{ color:'var(--accent2)',fontWeight:600,minWidth:80,flexShrink:0 }}>@{c.user?.username||'user'}</span>
                <span style={{ color:'var(--text2)' }}>{c.content}</span>
              </div>
            ))
          }
        </div>

        <div style={{ display:'flex',gap:8,marginTop:18,justifyContent:'flex-end' }}>
          <button className="btn btn-danger" onClick={()=>{ onDelete(post); onClose() }}><Trash2 size={14}/> Delete Post</button>
          <button className="btn btn-ghost" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  )
}

export default function Posts() {
  const [posts, setPosts]   = useState([])
  const [total, setTotal]   = useState(0)
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [page, setPage]     = useState(1)
  const PER = 25

  const load = useCallback(async (q='', type='all', pg=1) => {
    setLoading(true)
    try {
      const data = await adminGetPosts({ q, type: type==='all'?'':type, page: pg, page_size: PER })
      setPosts(data?.posts || [])
      setTotal(data?.total || 0)
    } catch(e) {
      toast.error('Failed to load posts')
    } finally { setLoading(false) }
  }, [])

  useEffect(() => { load() }, [load])

  useEffect(() => {
    const t = setTimeout(() => { setPage(1); load(search, filter, 1) }, 350)
    return () => clearTimeout(t)
  }, [search, filter, load])

  const handleDelete = async (post) => {
    if (!confirm(`Delete post #${post.id}?`)) return
    try {
      await adminDeletePost(post.id)
      setPosts(ps => ps.filter(p => p.id !== post.id))
      setTotal(t => t - 1)
      toast.success('Post deleted')
    } catch { toast.error('Failed to delete') }
  }

  const totalPages = Math.ceil(total / PER)
  const goPage = pg => { setPage(pg); load(search, filter, pg) }

  const mediaIcon = t => t==='video'?<Play size={11}/>:t==='image'?<Img size={11}/>:<FileText size={11}/>
  const mediaBadge = t => t==='video'?'badge-red':t==='image'?'badge-blue':'badge-yellow'

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Posts & Videos</div>
          <div className="page-subtitle">{total.toLocaleString()} total posts</div>
        </div>
        <div style={{ display:'flex',gap:8 }}>
          <div className="search-bar" style={{ minWidth:240 }}>
            <Search size={14}/>
            <input type="search" placeholder="Search posts…" value={search}
              onChange={e=>setSearch(e.target.value)}/>
          </div>
          <select value={filter} onChange={e=>{ setFilter(e.target.value); setPage(1); load(search,e.target.value,1) }} style={{ width:'auto' }}>
            <option value="all">All Types</option>
            <option value="video">Video</option>
            <option value="image">Image</option>
            <option value="text">Text</option>
          </select>
          <button className="btn btn-ghost" onClick={()=>load(search,filter,page)}><RefreshCw size={14}/> Refresh</button>
        </div>
      </div>

      <div className="card" style={{ padding:0 }}>
        {loading ? <div className="loading"><RefreshCw size={16} style={{ animation:'spin 1s linear infinite' }}/> Loading…</div> :
          posts.length===0 ? <div className="empty" style={{ padding:'50px 0' }}><FileText size={40}/><p>No posts found</p></div> : (
          <>
            <table>
              <thead>
                <tr><th>Preview</th><th>Content</th><th>Author</th><th>Type</th><th>Stats</th><th>Date</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {posts.map(p=>(
                  <tr key={p.id}>
                    <td style={{ width:70 }}>
                      <div style={{ width:56,height:44,background:'var(--surface2)',borderRadius:8,overflow:'hidden',display:'flex',alignItems:'center',justifyContent:'center' }}>
                        {p.media_type==='image'&&p.media_url
                          ? <img src={p.media_url} style={{ width:'100%',height:'100%',objectFit:'cover' }} alt=""/>
                          : p.media_type==='video' ? <span style={{ fontSize:20 }}>🎬</span>
                          : <FileText size={18} color="var(--text3)"/>}
                      </div>
                    </td>
                    <td style={{ maxWidth:220 }}>
                      <div className="truncate" style={{ fontSize:13 }}>{p.content||'(no caption)'}</div>
                      {p.hashtags && (
                        <div style={{ display:'flex',gap:3,flexWrap:'wrap',marginTop:4 }}>
                          {(Array.isArray(p.hashtags)?p.hashtags:p.hashtags.split(',')).slice(0,3).filter(Boolean).map(h=>(
                            <span key={h} className="chip" style={{ fontSize:10 }}>#{h.trim()}</span>
                          ))}
                        </div>
                      )}
                    </td>
                    <td style={{ fontSize:12 }}>
                      <div style={{ fontWeight:600 }}>{p.user?.full_name||p.user?.username||`#${p.user_id}`}</div>
                      <div style={{ color:'var(--text3)' }}>@{p.user?.username||''}</div>
                    </td>
                    <td><span className={`badge ${mediaBadge(p.media_type)}`}>{mediaIcon(p.media_type)} {p.media_type||'text'}</span></td>
                    <td style={{ fontSize:11,color:'var(--text3)',whiteSpace:'nowrap' }}>
                      <div>❤ {(p.like_count||0).toLocaleString()}</div>
                      <div>💬 {(p.comment_count||0).toLocaleString()}</div>
                      <div>👁 {(p.view_count||0).toLocaleString()}</div>
                    </td>
                    <td style={{ fontSize:11,color:'var(--text3)',whiteSpace:'nowrap' }}>
                      {p.created_at?new Date(p.created_at).toLocaleDateString():'—'}
                    </td>
                    <td>
                      <div style={{ display:'flex',gap:5 }}>
                        <button className="btn btn-ghost" style={{ padding:'5px 8px' }} onClick={()=>setSelected(p)}><Eye size={13}/></button>
                        <button className="btn btn-danger" style={{ padding:'5px 8px' }} onClick={()=>handleDelete(p)}><Trash2 size={13}/></button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {totalPages>1 && (
              <div style={{ display:'flex',alignItems:'center',justifyContent:'space-between',padding:'12px 16px',borderTop:'1px solid var(--border)' }}>
                <span style={{ color:'var(--text3)',fontSize:12 }}>Page {page} of {totalPages} · {total} posts</span>
                <div style={{ display:'flex',gap:6 }}>
                  <button className="btn btn-ghost" disabled={page===1} onClick={()=>goPage(page-1)} style={{ padding:'5px 10px' }}><ChevronLeft size={14}/></button>
                  {Array.from({length:Math.min(5,totalPages)},(_,i)=>{
                    const pg=Math.max(1,Math.min(page-2,totalPages-4))+i
                    return <button key={pg} onClick={()=>goPage(pg)} style={{ padding:'5px 10px',border:'none',cursor:'pointer',borderRadius:6,background:pg===page?'var(--accent)':'var(--surface2)',color:pg===page?'#fff':'var(--text2)',fontSize:12 }}>{pg}</button>
                  })}
                  <button className="btn btn-ghost" disabled={page===totalPages} onClick={()=>goPage(page+1)} style={{ padding:'5px 10px' }}><ChevronRight size={14}/></button>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {selected && <PostModal post={selected} onClose={()=>setSelected(null)} onDelete={handleDelete}/>}
      <style>{`@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}`}</style>
    </div>
  )
}
