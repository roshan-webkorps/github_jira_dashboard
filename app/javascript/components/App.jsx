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
import AiSearchModal from './AiSearchModal'
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
  const [appType, setAppType] = useState('legacy')
  
  // AI Search states
  const [searchQuery, setSearchQuery] = useState('')
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [searchResult, setSearchResult] = useState(null)
  const [searchLoading, setSearchLoading] = useState(false)
  const [searchError, setSearchError] = useState(null)

  const timeframeOptions = [
    { value: '24h', label: '24 Hours' },
    { value: '7d', label: '7 Days' },
    { value: '1m', label: '1 Month' },
    { value: '6m', label: '6 Months' },
    { value: '1y', label: '1 Year' }
  ]

  const appTypeOptions = [
    { value: 'legacy', label: 'Legacy App' },
    { value: 'pioneer', label: 'Pioneer App' }
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

  // AI Search handlers
  const handleSearchSubmit = async (e) => {
    e.preventDefault()
    if (!searchQuery.trim()) return

    setSearchLoading(true)
    setSearchError(null)
    setSearchResult(null)
    setIsModalOpen(true)

    try {
      const response = await fetch('/api/ai-query', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ 
          query: searchQuery,
          app_type: appType 
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to process query')
      }

      setSearchResult(data)
    } catch (err) {
      setSearchError(err.message)
    } finally {
      setSearchLoading(false)
    }
  }

  const handleModalClose = () => {
    setIsModalOpen(false)
    setSearchResult(null)
    setSearchError(null)
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
          
          {/* AI Search Bar */}
          <div className="search-section">
            <form onSubmit={handleSearchSubmit} className="search-form">
              <div className="search-input-container">
                <input
                  type="text"
                  placeholder="Ask about your data... e.g., 'top developers by commits'"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="search-input"
                />
                <button type="submit" className="search-btn" disabled={!searchQuery.trim()}>
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M21 21L16.514 16.506L21 21ZM19 10.5C19 15.194 15.194 19 10.5 19C5.806 19 2 15.194 2 10.5C2 5.806 5.806 2 10.5 2C15.194 2 19 5.806 19 10.5Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                  </svg>
                </button>
              </div>
            </form>
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
      
      {/* AI Search Modal */}
      <AiSearchModal
        isOpen={isModalOpen}
        onClose={handleModalClose}
        result={searchResult}
        loading={searchLoading}
        error={searchError}
      />
    </div>
  )
}

export default App
