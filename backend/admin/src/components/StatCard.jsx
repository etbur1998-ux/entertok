import React from 'react'

export default function StatCard({ label, value, icon: Icon, color, bg, change, changeUp }) {
  return (
    <div className="stat-card">
      <div className="stat-icon" style={{ background: bg }}>
        <Icon size={20} color={color} />
      </div>
      <div>
        <div className="stat-value" style={{ color }}>
          {value?.toLocaleString?.() ?? value ?? '—'}
        </div>
        <div className="stat-label">{label}</div>
        {change && (
          <div className={`stat-change ${changeUp !== false ? 'stat-up' : 'stat-down'}`}>
            {changeUp !== false ? '↑' : '↓'} {change}
          </div>
        )}
      </div>
    </div>
  )
}
