import React from 'react'

export default function Pagination({ page, total, perPage, onChange }) {
  const totalPages = Math.ceil(total / perPage)
  if (totalPages <= 1) return null
  const pages = []
  const start = Math.max(1, page - 2)
  const end = Math.min(totalPages, page + 2)
  for (let i = start; i <= end; i++) pages.push(i)

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '12px 16px', borderTop: '1px solid var(--border)', justifyContent: 'flex-end' }}>
      <span style={{ color: 'var(--text3)', fontSize: 12, marginRight: 8 }}>
        {(page - 1) * perPage + 1}–{Math.min(page * perPage, total)} of {total}
      </span>
      <button className="btn btn-ghost" style={{ padding: '5px 10px', fontSize: 12 }}
        disabled={page === 1} onClick={() => onChange(1)}>«</button>
      <button className="btn btn-ghost" style={{ padding: '5px 10px', fontSize: 12 }}
        disabled={page === 1} onClick={() => onChange(page - 1)}>‹</button>
      {pages.map(p => (
        <button key={p}
          onClick={() => onChange(p)}
          style={{
            padding: '5px 10px', fontSize: 12, border: 'none', cursor: 'pointer',
            borderRadius: 6, fontWeight: p === page ? 700 : 400,
            background: p === page ? 'var(--accent)' : 'var(--surface2)',
            color: p === page ? '#fff' : 'var(--text2)'
          }}
        >{p}</button>
      ))}
      <button className="btn btn-ghost" style={{ padding: '5px 10px', fontSize: 12 }}
        disabled={page === totalPages} onClick={() => onChange(page + 1)}>›</button>
      <button className="btn btn-ghost" style={{ padding: '5px 10px', fontSize: 12 }}
        disabled={page === totalPages} onClick={() => onChange(totalPages)}>»</button>
    </div>
  )
}
