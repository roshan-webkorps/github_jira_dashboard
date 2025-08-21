// app/javascript/application.js
import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './components/App'

// Wait for DOM to be ready
document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('react-root')
  if (container) {
    const root = createRoot(container)
    root.render(<App />)
  }
})

export default App
