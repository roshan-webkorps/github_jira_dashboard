import React, { useState, useRef, useEffect } from 'react'
import { Bar, Doughnut } from 'react-chartjs-2'
import chatApiService from './chatApiService'

const ChatHomePage = () => {
  const [messages, setMessages] = useState([])
  const [inputValue, setInputValue] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState(null)
  const [appType, setAppType] = useState('pioneer')
  const messagesEndRef = useRef(null)
  const inputRef = useRef(null)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  useEffect(() => {
    inputRef.current?.focus()
  }, [])

  const getAppUrl = (metaName, defaultUrl) => {
    const meta = document.querySelector(`meta[name="${metaName}"]`)
    return meta?.getAttribute('content') || defaultUrl
  }

  const githubUrl = getAppUrl('github-app-url', 'http://localhost:3000')
  const salesforceUrl = getAppUrl('salesforce-app-url', 'http://localhost:3002')

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!inputValue.trim() || isLoading) return

    const userMessage = inputValue.trim()
    setInputValue('')
    setError(null)

    const userMsgId = Date.now()
    setMessages(prev => [...prev, {
      id: userMsgId,
      type: 'user',
      content: userMessage,
      timestamp: new Date()
    }])
    setIsLoading(true)

    try {
      const result = await chatApiService.sendQuery(userMessage, appType)
      
      const aiMsgId = Date.now() + 1
      setMessages(prev => [...prev, { 
        id: aiMsgId,
        type: 'ai',
        content: result,
        timestamp: new Date()
      }])
    } catch (err) {
      setError(err.message || 'Failed to get response')
      setMessages(prev => [...prev, {
        id: Date.now() + 1,
        type: 'ai',
        content: { error: err.message || 'Sorry, something went wrong. Please try again.' },
        timestamp: new Date()
      }])
    } finally {
      setIsLoading(false)
    }
  }

  const handleNewChat = async () => {
    try {
      await chatApiService.resetChat()
      setMessages([])
      setError(null)
      setInputValue('')
      inputRef.current?.focus()
    } catch (err) {
      console.error('Failed to reset chat:', err)
    }
  }

  const handleExampleClick = (text) => {
    setInputValue(text)
    inputRef.current?.focus()
  }

  const renderChart = (data, chartType) => {
    if (!data) return null

    const chartOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: 'top',
        },
      },
      scales: chartType === 'bar' ? {
        y: {
          beginAtZero: true
        }
      } : undefined
    }

    const containerStyle = {
      height: '250px',
      marginBottom: '1rem'
    }

    switch (chartType) {
      case 'bar':
        return (
          <div style={containerStyle}>
            <Bar data={data} options={chartOptions} />
          </div>
        )
      case 'pie':
        return (
          <div style={containerStyle}>
            <Doughnut data={data} options={chartOptions} />
          </div>
        )
      default:
        return null
    }
  }

  const renderTable = (data) => {
    if (!data || !data.headers) return null

    return (
      <div className="table-container" style={{ marginBottom: '1rem' }}>
        <table className="results-table">
          <thead>
            <tr>
              {data.headers.map((header, index) => (
                <th key={index}>{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {data.rows.map((row, index) => (
              <tr key={index}>
                {row.map((cell, cellIndex) => (
                  <td key={cellIndex}>{cell}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )
  }

  const formatTextResponse = (text) => {
    if (!text) return <p>{text}</p>
    
    const paragraphs = text.split(/\n\s*\n/)
    
    return paragraphs.map((paragraph, pIndex) => {
      const trimmed = paragraph.trim()
      const lines = trimmed.split('\n').filter(line => line.trim())
      
      if (trimmed.match(/^(Strengths|Improvements|Summary Table):/i)) {
        const [header, ...content] = trimmed.split(/:\s*/)
        return (
          <div key={pIndex} style={{ marginBottom: '1.5rem' }}>
            <h4 style={{ 
              fontWeight: 'bold', 
              marginBottom: '0.5rem',
              fontSize: '1rem',
              color: '#1f2937'
            }}>
              {header}:
            </h4>
            <div style={{ paddingLeft: '0.5rem' }}>
              {formatContent(content.join(': '))}
            </div>
          </div>
        )
      }
      
      const hasNumbers = lines.some(line => /^\d+\.\s/.test(line.trim()))
      
      if (hasNumbers) {
        const listItems = []
        let currentItem = ''
        
        lines.forEach(line => {
          const trimmed = line.trim()
          const numberMatch = trimmed.match(/^(\d+)\.\s(.+)/)
          
          if (numberMatch) {
            if (currentItem) {
              listItems.push(currentItem)
            }
            currentItem = numberMatch[2]
          } else if (trimmed && currentItem) {
            currentItem += ' ' + trimmed
          }
        })
        
        if (currentItem) {
          listItems.push(currentItem)
        }
        
        return (
          <ol key={pIndex} style={{ marginBottom: '1rem', paddingLeft: '1.5rem' }}>
            {listItems.map((item, index) => (
              <li key={index} style={{ marginBottom: '0.5rem', lineHeight: '1.5' }}>
                {renderMarkdown(item)}
              </li>
            ))}
          </ol>
        )
      } else {
        return (
          <p key={pIndex} style={{ marginBottom: '1rem', lineHeight: '1.5' }}>
            {renderMarkdown(trimmed)}
          </p>
        )
      }
    })
  }

  const formatContent = (text) => {
    const lines = text.split('\n').filter(line => line.trim())
    return lines.map((line, index) => (
      <p key={index} style={{ marginBottom: '0.5rem', lineHeight: '1.5' }}>
        {renderMarkdown(line.trim())}
      </p>
    ))
  }

  const renderMarkdown = (text) => {
    const parts = text.split(/(\*\*.*?\*\*)/)
    
    return parts.map((part, index) => {
      if (part.startsWith('**') && part.endsWith('**')) {
        const boldText = part.slice(2, -2)
        return <strong key={index}>{boldText}</strong>
      }
      return <span key={index}>{part}</span>
    })
  }

  const renderMessage = (message) => {
    if (message.type === 'user') {
      return (
        <div key={message.id} className="message-wrapper user">
          <div className="message-avatar">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
            </svg>
          </div>
          <div className="message-content">
            <div className="message-text">
              <p>{message.content}</p>
            </div>
            <div className="message-time">
              {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </div>
          </div>
        </div>
      )
    }

    // AI message
    const content = message.content
    
    if (content.error) {
      return (
        <div key={message.id} className="message-wrapper assistant">
          <div className="message-avatar">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
            </svg>
          </div>
          <div className="message-content">
            <div className="message-text error">
              <p className="error-text">{content.error}</p>
              <div className="query-suggestions">
                <p><strong>Try these examples:</strong></p>
                <ul>
                  <li>"Top 5 developers by commits"</li>
                  <li>"Show me open pull requests"</li>
                  <li>"Which repositories have the most activity?"</li>
                  <li>"Tickets completed this month"</li>
                </ul>
              </div>
            </div>
            <div className="message-time">
              {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </div>
          </div>
        </div>
      )
    }

    // Handle conversational/text responses
    if (content.chart_type === 'text') {
      return (
        <div key={message.id} className="message-wrapper assistant">
          <div className="message-avatar">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
            </svg>
          </div>
          <div className="message-content">
            <div className="message-text">
              <div className="text-response">
                {formatTextResponse(content.response)}
              </div>
            </div>
            <div className="message-time">
              {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </div>
          </div>
        </div>
      )
    }

    // Handle data visualization responses
    return (
      <div key={message.id} className="message-wrapper assistant">
        <div className="message-avatar">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
          </svg>
        </div>
        <div className="message-content">
          <div className="message-text">
            {content.description && (
              <div className="result-description">
                <h4>{content.description}</h4>
              </div>
            )}
            
            {content.chart_type === 'table' ? 
              renderTable(content.data) : 
              renderChart(content.data, content.chart_type)
            }

            {content.summary && (
              <div className="summary-content">
                {formatTextResponse(content.summary)}
              </div>
            )}
          </div>
          <div className="message-time">
            {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </div>
        </div>
      </div>
    )
  }

  const hasMessages = messages.length > 0

  return (
    <div className="chat-home-wrapper">
      {/* Top Navigation */}
      <nav className="chat-nav">
        <div className="chat-nav-content">
          <div className="nav-left">
            <h1 className="nav-logo">Analytics AI</h1>
            <div className="nav-tabs">
              <a href={githubUrl} className="nav-tab active">
                <svg className="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
                </svg>
                GitHub & Jira Analytics
              </a>
              <a href={salesforceUrl} className="nav-tab">
                <svg className="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8.5 11.5a.5.5 0 0 1-.5-.5v-7a.5.5 0 0 1 1 0v7a.5.5 0 0 1-.5.5z"/>
                  <path d="M4 3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H4zm0-1h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z"/>
                </svg>
                Salesforce Analytics
              </a>
            </div>
          </div>
          
          <div className="nav-right">
            {hasMessages && (
              <>
                <div className="app-type-dropdown">
                  <label htmlFor="appType">App Type:</label>
                  <select 
                    id="appType"
                    value={appType} 
                    onChange={(e) => setAppType(e.target.value)}
                  >
                    <option value="pioneer">Pro</option>
                    <option value="legacy">Classic</option>
                  </select>
                </div>
                
                <button 
                  onClick={handleNewChat}
                  className="new-chat-button"
                  disabled={isLoading}
                >
                  <svg className="button-icon" viewBox="0 0 16 16" fill="currentColor">
                    <path d="M2 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v13.5a.5.5 0 0 1-.777.416L8 13.101l-5.223 2.815A.5.5 0 0 1 2 15.5V2zm2-1a1 1 0 0 0-1 1v12.566l4.723-2.482a.5.5 0 0 1 .554 0L13 14.566V2a1 1 0 0 0-1-1H4z"/>
                  </svg>
                  New Chat
                </button>
              </>
            )}
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <div className="chat-main">
        {!hasMessages ? (
          // Welcome Screen
          <div className="welcome-screen">
            <div className="welcome-content">
              <div className="welcome-header">
                <div className="welcome-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                  </svg>
                </div>
                <h1 className="welcome-title">Unified Engineering Intelligence</h1>
                <p className="welcome-description">
                  Ask questions about your team’s performance, commits, meetings, and tickets — all in one place.
                </p>
              </div>

              <div className="welcome-controls">
                <div className="app-type-selector-welcome">
                  <label htmlFor="appTypeWelcome">App Type:</label>
                  <select 
                    id="appTypeWelcome"
                    value={appType} 
                    onChange={(e) => setAppType(e.target.value)}
                  >
                    <option value="pioneer">Pro</option>
                    <option value="legacy">Classic</option>
                  </select>
                </div>
              </div>

              <div className="example-prompts">
                <p className="prompts-title">Try asking:</p>
                <div className="prompts-grid">
                  <button 
                    className="prompt-card"
                    onClick={() => handleExampleClick("How was the performance of our team last month?")}
                  >
                    <div className="prompt-icon">📊</div>
                    <div className="prompt-text">How was the performance of our team last month?</div>
                  </button>
                  <button 
                    className="prompt-card"
                    onClick={() => handleExampleClick("Show me the top contributors")}
                  >
                    <div className="prompt-icon">👥</div>
                    <div className="prompt-text">Show me the top contributors</div>
                  </button>
                  <button 
                    className="prompt-card"
                    onClick={() => handleExampleClick("What are the open tickets?")}
                  >
                    <div className="prompt-icon">🎫</div>
                    <div className="prompt-text">What are the open tickets?</div>
                  </button>
                  <button 
                    className="prompt-card"
                    onClick={() => handleExampleClick("Analyze our pull request trends")}
                  >
                    <div className="prompt-icon">🔄</div>
                    <div className="prompt-text">Analyze our pull request trends</div>
                  </button>
                </div>
              </div>
            </div>
          </div>
        ) : (
          // Chat Messages
          <div className="chat-messages-container">
            <div className="chat-messages">
              {messages.map(renderMessage)}
              
              {isLoading && (
                <div className="message-wrapper assistant">
                  <div className="message-avatar">
                    <svg viewBox="0 0 24 24" fill="currentColor">
                      <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
                    </svg>
                  </div>
                  <div className="message-content">
                    <div className="typing-indicator">
                      <span></span>
                      <span></span>
                      <span></span>
                    </div>
                  </div>
                </div>
              )}
              
              <div ref={messagesEndRef} />
            </div>
          </div>
        )}
      </div>

      {/* Input Area */}
      <div className="chat-input-area">
        <div className="chat-input-wrapper">
          {error && (
            <div className="error-message">
              <svg viewBox="0 0 16 16" fill="currentColor">
                <path d="M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14zm0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16z"/>
                <path d="M7.002 11a1 1 0 1 1 2 0 1 1 0 0 1-2 0zM7.1 4.995a.905.905 0 1 1 1.8 0l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 4.995z"/>
              </svg>
              {error}
            </div>
          )}
          
          <form onSubmit={handleSubmit} className="input-form">
            <input
              ref={inputRef}
              type="text"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              placeholder="Ask about your team's activity, commits, tickets, etc..."
              className="message-input"
              disabled={isLoading}
            />
            <button 
              type="submit" 
              className="send-button"
              disabled={!inputValue.trim() || isLoading}
            >
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
              </svg>
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}

export default ChatHomePage
