import React, { useState, useRef, useEffect } from 'react'
import { Bar, Doughnut } from 'react-chartjs-2'

const AiChatModal = ({ isOpen, onClose, onQuery, onNewTopic }) => {
  const [messages, setMessages] = useState([])
  const [inputValue, setInputValue] = useState('')
  const [loading, setLoading] = useState(false)
  const messagesEndRef = useRef(null)
  const inputRef = useRef(null)

  // Auto-scroll to bottom when new messages are added
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Focus input when modal opens
  useEffect(() => {
    if (isOpen && inputRef.current) {
      setTimeout(() => inputRef.current?.focus(), 100)
    }
  }, [isOpen])

  useEffect(() => {
    const clearContextOnLoad = async () => {
      try {
        const status = await chatApiService.checkChatStatus();
        if (status.has_context) {
          // Optionally reset chat on page load, or just inform user
          // await onNewTopic(); // Uncomment if you want auto-reset
        }
      } catch (error) {
        console.error('Failed to check chat status:', error);
      }
    };
    
    if (isOpen) {
      clearContextOnLoad();
    }
  }, [isOpen]);

  useEffect(() => {
    if (isOpen) {
      // Lock body scroll
      document.body.style.overflow = 'hidden';
    } else {
      // Restore body scroll
      document.body.style.overflow = '';
    }
    
    // Cleanup on unmount
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  if (!isOpen) return null

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!inputValue.trim() || loading) return

    const userMessage = inputValue.trim()
    setInputValue('')
    setLoading(true)

    // Add user message to chat
    const userMsgId = Date.now()
    setMessages(prev => [...prev, {
      id: userMsgId,
      type: 'user',
      content: userMessage,
      timestamp: new Date()
    }])

    try {
      // Call the query function (passed from parent component)
      const result = await onQuery(userMessage, {})
      
      // Add AI response to chat
      const aiMsgId = Date.now() + 1
      setMessages(prev => [...prev, {
        id: aiMsgId,
        type: 'ai',
        content: result,
        timestamp: new Date()
      }])

    } catch (error) {
      console.error('Query error:', error)
      setMessages(prev => [...prev, {
        id: Date.now() + 1,
        type: 'ai',
        content: { error: error.message || 'Sorry, something went wrong. Please try again.' },
        timestamp: new Date()
      }])
    } finally {
      setLoading(false)
    }
  }

  const handleNewTopic = async () => {
    setMessages([])
    try {
      await onNewTopic()
    } catch (error) {
      console.error('Failed to reset chat:', error)
    }
    if (inputRef.current) {
      inputRef.current.focus()
    }
  }

  const handleExampleClick = (exampleQuery) => {
    setInputValue(exampleQuery)
    if (inputRef.current) {
      inputRef.current.focus()
    }
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
    if (!text) return <p>{text}</p>;
    
    // Split text into paragraphs first
    const paragraphs = text.split(/\n\s*\n/);
    
    return paragraphs.map((paragraph, pIndex) => {
      const lines = paragraph.split('\n').filter(line => line.trim());
      
      // Check if this paragraph contains a numbered list
      const hasNumbers = lines.some(line => /^\d+\.\s/.test(line.trim()));
      
      if (hasNumbers) {
        const listItems = [];
        let currentItem = '';
        
        lines.forEach(line => {
          const trimmed = line.trim();
          const numberMatch = trimmed.match(/^(\d+)\.\s(.+)/);
          
          if (numberMatch) {
            if (currentItem) {
              listItems.push(currentItem);
            }
            currentItem = numberMatch[2];
          } else if (trimmed && currentItem) {
            currentItem += ' ' + trimmed;
          }
        });
        
        if (currentItem) {
          listItems.push(currentItem);
        }
        
        return (
          <ol key={pIndex} style={{ marginBottom: '1rem', paddingLeft: '1.5rem' }}>
            {listItems.map((item, index) => (
              <li key={index} style={{ marginBottom: '0.5rem', lineHeight: '1.5' }}>
                {item}
              </li>
            ))}
          </ol>
        );
      } else {
        // Regular paragraph
        return (
          <p key={pIndex} style={{ marginBottom: '1rem', lineHeight: '1.5' }}>
            {paragraph.trim()}
          </p>
        );
      }
    });
  };

  const renderMessage = (message) => {
    if (message.type === 'user') {
      return (
        <div key={message.id} className="message user-message">
          <div className="message-content">
            <p>{message.content}</p>
          </div>
          <div className="message-time">
            {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </div>
        </div>
      )
    }

    // AI message
    const content = message.content
    
    if (content.error) {
      return (
        <div key={message.id} className="message ai-message error">
          <div className="message-content">
            <p className="error-message">{content.error}</p>
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
      )
    }

    // Handle conversational/text responses
    if (content.chart_type === 'text') {
      return (
        <div key={message.id} className="message ai-message">
          <div className="message-content">
            <div className="text-response">
              {formatTextResponse(content.response)}
            </div>
          </div>
          <div className="message-time">
            {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </div>
        </div>
      )
    }

    // Handle data visualization responses
    return (
      <div key={message.id} className="message ai-message">
        <div className="message-content">
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
            <div className="ai-summary">
              <div className="summary-content">
                <p>{content.summary}</p>
              </div>
            </div>
          )}

          {content.raw_results && (
            <div className="result-count">
              <small>
                Found {content.raw_results.length} result{content.raw_results.length !== 1 ? 's' : ''}
              </small>
            </div>
          )}
        </div>
        <div className="message-time">
          {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </div>
      </div>
    )
}

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content chat-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <div className="chat-header-content">
            <h3>AI Analytics Chat</h3>
            {messages.length > 0 && (
              <button 
                className="new-topic-btn"
                onClick={handleNewTopic}
                title="Start new conversation"
              >
                New Topic
              </button>
            )}
          </div>
          <button className="modal-close" onClick={onClose}>×</button>
        </div>
        
        <div className="chat-container">
          <div className="messages-container">
            {messages.length === 0 && (
              <div className="welcome-message">
                <div className="welcome-content">
                  <h4>Hi! I'm your analytics assistant</h4>
                  <p>Ask me anything about your team's GitHub and Jira data:</p>
                  <div className="example-queries">
                    <button 
                      className="example-query"
                      onClick={() => handleExampleClick("Top 5 most active developers in last 1 month")}
                    >
                      "Top 5 most active developers in last 1 month"
                    </button>
                    <button 
                      className="example-query"
                      onClick={() => handleExampleClick("Show me open tickets")}
                    >
                      "Show me open tickets"
                    </button>
                  </div>
                </div>
              </div>
            )}

            {messages.map(renderMessage)}

            {loading && (
              <div className="message ai-message loading">
                <div className="message-content">
                  <div className="typing-indicator">
                    <div className="spinner"></div>
                    <span>Analyzing your query...</span>
                  </div>
                </div>
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          <div className="chat-input-container">
            <form onSubmit={handleSubmit} className="chat-form">
              <div className="input-group">
                <input
                  ref={inputRef}
                  type="text"
                  value={inputValue}
                  onChange={(e) => setInputValue(e.target.value)}
                  placeholder="Ask about your team's activity, commits, tickets, etc..."
                  disabled={loading}
                  className="chat-input"
                />
                <button 
                  type="submit" 
                  disabled={!inputValue.trim() || loading}
                  className="send-button"
                >
                  {loading ? '⋯' : '▶'}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  )
}

export default AiChatModal
