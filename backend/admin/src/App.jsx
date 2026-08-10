import React from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Users from './pages/Users'
import Posts from './pages/Posts'
import Products from './pages/Products'
import LiveStreams from './pages/LiveStreams'
import Ads from './pages/Ads'
import Messages from './pages/Messages'
import Reports from './pages/Reports'
import Settings from './pages/Settings'

import Boosts from './pages/Boosts'

function Protected({ children }) {
  return localStorage.getItem('admin_token')
    ? children
    : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <BrowserRouter>
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: '#1a1a24',
            color: '#f1f5f9',
            border: '1px solid #2a2a3a',
            fontSize: 13,
          }
        }}
      />
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<Protected><Layout /></Protected>}>
          <Route index element={<Dashboard />} />
          <Route path="users" element={<Users />} />
          <Route path="posts" element={<Posts />} />
          <Route path="products" element={<Products />} />
          <Route path="live" element={<LiveStreams />} />
          <Route path="ads" element={<Ads />} />
          <Route path="messages" element={<Messages />} />
          <Route path="reports" element={<Reports />} />
          <Route path="boosts" element={<Boosts />} />
          <Route path="settings" element={<Settings />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
