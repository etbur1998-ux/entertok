import React, { useState, useEffect } from 'react'
import { getProducts, deleteProduct } from '../api'
import toast from 'react-hot-toast'
import { Trash2, Eye, RefreshCw, Star, ShoppingBag, X } from 'lucide-react'

function ProductModal({ product: p, onClose }) {
  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <span className="modal-title" style={{ marginBottom: 0 }}>Product Details</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--text3)', cursor: 'pointer' }}><X size={20} /></button>
        </div>
        {p.image_url && (
          <img src={p.image_url} alt={p.name}
            style={{ width: '100%', height: 200, objectFit: 'cover', borderRadius: 10, marginBottom: 16 }} />
        )}
        <div style={{ display: 'grid', gap: 10, fontSize: 13 }}>
          <h3 style={{ fontSize: 18, fontWeight: 700 }}>{p.name}</h3>
          <p style={{ color: 'var(--text2)', lineHeight: 1.6 }}>{p.description}</p>
          {[
            ['Price', `${p.price} ${p.currency || 'USD'}`],
            ['Category', p.category],
            ['Stock', p.stock?.toString()],
            ['Rating', `⭐ ${p.rating || 0}`],
            ['Likes', `❤ ${p.like_count || 0}`],
            ['Seller ID', `#${p.seller_id}`],
            ['Created', p.created_at ? new Date(p.created_at).toLocaleDateString() : '—'],
          ].map(([k, v]) => v ? (
            <div key={k} style={{ display: 'flex', gap: 12 }}>
              <span style={{ color: 'var(--text3)', minWidth: 90 }}>{k}</span>
              <span>{v}</span>
            </div>
          ) : null)}
        </div>
      </div>
    </div>
  )
}

export default function Products() {
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)
  const [filter, setFilter] = useState('all')
  const [categories, setCategories] = useState([])

  const load = async () => {
    setLoading(true)
    try {
      const data = await getProducts({ limit: 100 })
      const prods = data?.products || data || []
      setProducts(prods)
      const cats = [...new Set(prods.map(p => p.category).filter(Boolean))]
      setCategories(cats)
    } catch { toast.error('Failed to load products') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const handleDelete = async (p) => {
    if (!confirm(`Delete "${p.name}"?`)) return
    try {
      await deleteProduct(p.id)
      setProducts(ps => ps.filter(x => x.id !== p.id))
      toast.success('Product deleted')
    } catch { toast.error('Failed to delete') }
  }

  const filtered = filter === 'all' ? products : products.filter(p => p.category === filter)

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Marketplace</div>
          <div className="page-subtitle">{products.length} products</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <select value={filter} onChange={e => setFilter(e.target.value)} style={{ width: 'auto' }}>
            <option value="all">All Categories</option>
            {categories.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
          <button className="btn btn-ghost" onClick={load}><RefreshCw size={14} /> Refresh</button>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))', gap: 16 }}>
        {loading ? <div className="loading" style={{ gridColumn: '1/-1' }}><RefreshCw size={16} />Loading...</div> :
          filtered.map(p => (
            <div key={p.id} className="card" style={{ padding: 0, overflow: 'hidden' }}>
              <div style={{ height: 160, background: 'var(--surface2)', position: 'relative', overflow: 'hidden' }}>
                {p.image_url
                  ? <img src={p.image_url} alt={p.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  : <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <ShoppingBag size={40} color="var(--text3)" />
                    </div>
                }
                {p.category && <span className="badge badge-purple" style={{ position: 'absolute', top: 8, left: 8 }}>{p.category}</span>}
              </div>
              <div style={{ padding: '12px 14px' }}>
                <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }} className="truncate">{p.name}</div>
                <div style={{ color: 'var(--text3)', fontSize: 12, marginBottom: 10 }} className="truncate">{p.description}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
                  <span style={{ fontWeight: 700, color: 'var(--accent2)', fontSize: 16 }}>{p.price} {p.currency || 'USD'}</span>
                  <span style={{ color: 'var(--text3)', fontSize: 11, marginLeft: 'auto' }}>Stock: {p.stock}</span>
                </div>
                <div style={{ display: 'flex', gap: 8, fontSize: 11, color: 'var(--text3)', marginBottom: 12 }}>
                  <span><Star size={10} style={{ verticalAlign: 'middle' }} /> {p.rating || 0}</span>
                  <span>❤ {p.like_count || 0}</span>
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button className="btn btn-ghost" style={{ flex: 1, justifyContent: 'center', fontSize: 12 }} onClick={() => setSelected(p)}>
                    <Eye size={13} /> View
                  </button>
                  <button className="btn btn-danger" style={{ padding: '7px 10px' }} onClick={() => handleDelete(p)}>
                    <Trash2 size={13} />
                  </button>
                </div>
              </div>
            </div>
          ))
        }
      </div>

      {selected && <ProductModal product={selected} onClose={() => setSelected(null)} />}
    </div>
  )
}
