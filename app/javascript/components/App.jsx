import React, { useState, useEffect } from 'react'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  ArcElement,
  LineElement,
  PointElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js'
import AiChatModal from './AiChatModal'  // Updated chat component
import chatApiService from './chatApiService'  // API service
import {
  CommitActivityChart,
  CompletedTicketsChart,
  PullRequestStatusChart,
  JiraTicketStatusChart,
  ActivityTimelineChart,
  CommitsPerRepositoryChart,
  TicketPriorityChart,
  LanguageDistributionChart,
  PullRequestActivityChart,
  TicketTypeCompletionChart,
  CodeImpactChart,
  CodeChangesByDeveloperAndRepoChart
} from './ChartComponents'

ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  ArcElement,
  LineElement,
  PointElement,
  Title,
  Tooltip,
  Legend
)

const App = () => {
  const [dashboardData, setDashboardData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [timeframe, setTimeframe] = useState('24h')
  const [appType, setAppType] = useState('pioneer')
  
  // AI Chat states - Updated for conversational interface
  const [isChatOpen, setIsChatOpen] = useState(false)

  const timeframeOptions = [
    { value: '24h', label: '24 Hours' },
    { value: '7d', label: '7 Days' },
    { value: '1m', label: '1 Month' },
    { value: '6m', label: '6 Months' },
    { value: '1y', label: '1 Year' }
  ]

  const appTypeOptions = [
    { value: 'pioneer', label: 'Pioneer App' },
    { value: 'legacy', label: 'Legacy App' }
  ]

  useEffect(() => {
    fetchDashboardData()
  }, [timeframe, appType])

  const fetchDashboardData = async () => {
    try {
      setLoading(true)
      const response = await fetch(`/api/dashboard?timeframe=${timeframe}&app_type=${appType}`)
      if (!response.ok) {
        throw new Error('Failed to fetch dashboard data')
      }
      const data = await response.json()
      setDashboardData(data)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleTimeframeChange = (newTimeframe) => {
    setTimeframe(newTimeframe)
  }

  const handleAppTypeChange = (newAppType) => {
    setAppType(newAppType)
  }

  // AI Chat handlers - Updated for conversational interface
  const handleOpenChat = () => {
    setIsChatOpen(true)
  }

  const handleCloseChat = () => {
    setIsChatOpen(false)
  }

  // This function will be passed to the chat modal
  const handleChatQuery = async (query, chatService) => {
    try {
      const currentAppType = chatApiService.getCurrentAppType()
      const result = await chatApiService.sendQuery(query, currentAppType, chatService)
      return result
    } catch (error) {
      throw error
    }
  }

  const handleNewTopic = async () => {
    try {
      await chatApiService.resetChat()
    } catch (error) {
      console.error('Failed to reset chat:', error)
    }
  }

  if (loading) {
    return (
      <div className="loading-container">
        <h2>Loading Dashboard...</h2>
      </div>
    )
  }

  if (error) {
    return (
      <div className="error-container">
        <h2>Error</h2>
        <p>{error}</p>
        <button onClick={fetchDashboardData} className="retry-btn">
          Retry
        </button>
      </div>
    )
  }

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-content">
          <div className="header-text">
            <h1>GitHub & Jira Dashboard</h1>
          </div>
          
          {/* AI Chat Button - Replaces search bar */}
          <div className="search-section">
            <button 
              className="open-chat-btn"
              onClick={handleOpenChat}
            >
              <span className="search-icon">🔍</span>
              Ask AI about your data...
            </button>
          </div>
          
          <div className="controls-section">
            <div className="app-type-selector">
              <label htmlFor="appType">App Type:</label>
              <select 
                id="appType"
                value={appType} 
                onChange={(e) => handleAppTypeChange(e.target.value)}
                className="app-type-select"
              >
                {appTypeOptions.map(option => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>
            
            <div className="timeframe-selector">
              <label htmlFor="timeframe">Timeframe:</label>
              <select 
                id="timeframe"
                value={timeframe} 
                onChange={(e) => handleTimeframeChange(e.target.value)}
                className="timeframe-select"
              >
                {timeframeOptions.map(option => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </div>
      </header>
      
      <main className="app-main">
        {dashboardData?.summary && (
          <div className="stats-grid">
            <div className="stat-card">
              <h3>Active Developers</h3>
              <p className="stat-number">{dashboardData.summary.total_developers}</p>
              <p className="stat-label">Contributors</p>
            </div>
            
            <div className="stat-card">
              <h3>Repositories</h3>
              <p className="stat-number">{dashboardData.summary.total_repositories}</p>
              <p className="stat-label">Projects</p>
            </div>
            
            <div className="stat-card">
              <h3>Commits</h3>
              <p className="stat-number">{dashboardData.summary.total_commits}</p>
              <p className="stat-label">in {timeframeOptions.find(t => t.value === timeframe)?.label}</p>
            </div>
            
            <div className="stat-card">
              <h3>Pull Requests</h3>
              <p className="stat-number">{dashboardData.summary.total_pull_requests}</p>
              <p className="stat-label">in {timeframeOptions.find(t => t.value === timeframe)?.label}</p>
            </div>
            
            <div className="stat-card">
              <h3>Jira Tickets</h3>
              <p className="stat-number">{dashboardData.summary.total_tickets || 0}</p>
              <p className="stat-label">in {timeframeOptions.find(t => t.value === timeframe)?.label}</p>
            </div>
          </div>
        )}

        <div className="charts-section">
          <h2>Analytics Overview</h2>
          
          {/* Row 1: Developer Activity - GitHub Focus */}
          <div className="charts-grid-two">
            <CommitActivityChart dashboardData={dashboardData} />
            <PullRequestActivityChart dashboardData={dashboardData} />
          </div>

          {/* Row 2: Developer Activity - Jira Focus */}
          <div className="charts-grid-two">
            <CompletedTicketsChart dashboardData={dashboardData} />
            <TicketTypeCompletionChart dashboardData={dashboardData} />
          </div>

          {/* Row 3: Ticket Analysis */}
          <div className="charts-grid-two">
            <TicketPriorityChart dashboardData={dashboardData} />
            <JiraTicketStatusChart dashboardData={dashboardData} />
          </div>

          {/* Row 4: Timeline & Repository Insights */}
          <div className="charts-grid-two">
            <ActivityTimelineChart dashboardData={dashboardData} />
            <CommitsPerRepositoryChart dashboardData={dashboardData} />
          </div>

          {/* Row 5: Conditional Charts based on app_type */}
          <div className="charts-grid-two">
            {appType === 'legacy' ? (
              <>
                <CodeImpactChart dashboardData={dashboardData} />
                <CodeChangesByDeveloperAndRepoChart dashboardData={dashboardData} />
              </>
            ) : (
              <>
                <PullRequestStatusChart dashboardData={dashboardData} />
                <LanguageDistributionChart dashboardData={dashboardData} />
              </>
            )}
          </div>
        </div>
      </main>
      
      {/* AI Chat Modal - Updated */}
      <AiChatModal
        isOpen={isChatOpen}
        onClose={handleCloseChat}
        onQuery={handleChatQuery}
        onNewTopic={handleNewTopic}
      />
    </div>
  )
}

export default App
