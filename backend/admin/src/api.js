import axios from 'axios'

const api  = axios.create({ baseURL: '/api/v1' })
const raw  = axios.create({ baseURL: '' })

const auth = cfg => {
  const t = localStorage.getItem('admin_token')
  if (t) cfg.headers.Authorization = `Bearer ${t}`
  return cfg
}
api.interceptors.request.use(auth)
raw.interceptors.request.use(auth)
api.interceptors.response.use(r => r.data, e => {
  const data = e.response?.data
  const status = e.response?.status
  // 401 = not logged in or token expired
  if (status === 401) {
    localStorage.removeItem('admin_token')
    window.location.href = '/login'
  }
  throw data || { error: e.message || `HTTP ${status || 'error'}` }
})
raw.interceptors.response.use(r => r.data, e => {
  throw e.response?.data || { error: e.message || 'Network error' }
})

// Auth
export const login  = (email, pw) => api.post('/auth/login', { email, password: pw })
export const getMe  = ()           => api.get('/auth/me')

// Health / debug (top-level, proxied via /health & /debug)
export const getHealth    = () => raw.get('/health')
export const getDebugInfo = () => raw.get('/debug/info')

// ── Admin API (/api/v1/admin/*) ────────────────────────────────────────────
export const adminGetStats   = ()            => api.get('/admin/stats')
export const adminGetUsers   = (p = {})      => api.get('/admin/users',  { params: p })
export const adminGetPosts   = (p = {})      => api.get('/admin/posts',  { params: p })
export const adminDeletePost = id            => api.delete(`/admin/posts/${id}`)
export const adminBanUser    = id            => api.post(`/admin/users/${id}/ban`)
export const adminUnbanUser  = id            => api.post(`/admin/users/${id}/unban`)
export const adminVerifyUser = id            => api.post(`/admin/users/${id}/verify`)
export const adminGetAds     = (p = {})      => api.get('/admin/ads',    { params: p })
export const adminGetConversations  = (p={}) => api.get('/admin/conversations', { params: p })
export const adminGetMessages       = (id,p={}) => api.get(`/admin/conversations/${id}/messages`, { params: p })
export const adminDeleteMessage     = id     => api.delete(`/admin/messages/${id}`)
export const adminSendMessage       = (senderId, receiverId, content) =>
  api.post('/admin/messages/send', { sender_id: senderId, receiver_id: receiverId, content })

// ── Public / user APIs ─────────────────────────────────────────────────────
export const getUserPosts  = id => api.get(`/posts/user/${id}`)
export const getFollowers  = id => api.get(`/users/${id}/followers`)
export const getFollowing  = id => api.get(`/users/${id}/following`)
export const getComments   = id => api.get(`/posts/${id}/comments`)
export const deletePost    = id => api.delete(`/posts/${id}`)
export const getProducts   = (p = {}) => api.get('/products', { params: p })
export const deleteProduct = id       => api.delete(`/products/${id}`)
export const getLives      = ()       => api.get('/live')
export const endLiveStream = id       => api.post(`/live/${id}/end`)
export const getAds        = (p = {}) => adminGetAds(p).catch(() => ({ ads: [] }))
export const deleteAd      = id       => api.delete(`/ads/${id}`)
export const getAdStats    = id       => api.get(`/ads/${id}/stats`).catch(() => ({}))
export const getTrendingHashtags = () => api.get('/posts/hashtags/trending')
export const getReports    = ()       => api.get('/reports').catch(() => ({ reports: [] }))
export const getWallet     = ()       => api.get('/wallet').catch(() => null)

export default api
