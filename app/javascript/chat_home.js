import React from 'react'
import { createRoot } from 'react-dom/client'
import ChatHomePage from './components/ChatHomePage'

// Wait for DOM to be ready
document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('chat-home-root')
  if (container) {
    const root = createRoot(container)
    root.render(<ChatHomePage />)
  }
})

export default ChatHomePage
