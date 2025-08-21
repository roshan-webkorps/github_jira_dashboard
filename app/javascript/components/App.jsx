import React, { useState, useEffect } from 'react'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js'
import { Bar, Doughnut } from 'react-chartjs-2'
import AiSearchModal from './AiSearchModal'

ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend
)

const App = () => {
  const [dashboardData, setDashboardData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [timeframe, setTimeframe] = useState('24h')
  
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

  useEffect(() => {
    fetchDashboardData()
  }, [timeframe])

  const fetchDashboardData = async () => {
    try {
      setLoading(true)
      const response = await fetch(`/api/dashboard?timeframe=${timeframe}`)
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
        body: JSON.stringify({ query: searchQuery }),
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
    // Keep searchQuery - don't clear it
  }

  const clearSearch = () => {
    setSearchQuery('')
    setSearchResult(null)
    setSearchError(null)
  }

  const getCommitsChartData = () => {
    if (!dashboardData?.charts_data?.commits) {
      return {
        labels: ['Loading...'],
        datasets: [{ label: 'Commits', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' }]
      }
    }
    
    const { labels, datasets } = dashboardData.charts_data.commits
    
    // Convert developer datasets to Chart.js format
    const chartDatasets = []
    const colors = [
      'rgba(52, 152, 219, 0.6)',   // Blue
      'rgba(46, 204, 113, 0.6)',   // Green  
      'rgba(241, 196, 15, 0.6)',   // Yellow
      'rgba(231, 76, 60, 0.6)',    // Red
      'rgba(155, 89, 182, 0.6)',   // Purple
      'rgba(230, 126, 34, 0.6)',   // Orange
    ]
    
    let colorIndex = 0
    // Limit to top 6 developers to prevent legend overflow
    const sortedDevelopers = Object.entries(datasets)
      .map(([name, data]) => ({ name, data, total: data.reduce((sum, count) => sum + count, 0) }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 6)
    
    sortedDevelopers.forEach(({ name, data, total }) => {
      // Truncate long names
      const displayName = name.length > 15 ? name.substring(0, 15) + '...' : name
      
      chartDatasets.push({
        label: `${displayName} (${total})`,
        data: data,
        backgroundColor: colors[colorIndex % colors.length],
        borderColor: colors[colorIndex % colors.length].replace('0.6', '1'),
        borderWidth: 1,
      })
      colorIndex++
    })
    
    return { labels, datasets: chartDatasets }
  }

  const getPRStatusData = () => {
    if (!dashboardData?.charts_data?.pull_requests?.totals) {
      return {
        labels: ['Loading...'],
        datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
      }
    }
    
    const { open, closed_merged } = dashboardData.charts_data.pull_requests.totals
    return {
      labels: ['Open', 'Merged/Closed'],
      datasets: [
        {
          data: [open, closed_merged],
          backgroundColor: [
            'rgba(241, 196, 15, 0.6)',
            'rgba(46, 204, 113, 0.6)',
          ],
          borderColor: [
            'rgba(241, 196, 15, 1)',
            'rgba(46, 204, 113, 1)',
          ],
          borderWidth: 1,
        },
      ],
    }
  }

  const getTicketStatusData = () => {
    if (!dashboardData?.charts_data?.tickets?.totals) {
      return {
        labels: ['Loading...'],
        datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
      }
    }
    
    const { todo, in_progress, done, other } = dashboardData.charts_data.tickets.totals
    const labels = ['To Do', 'In Progress', 'Done']
    const data = [todo, in_progress, done]
    
    // Add "Other" if there are tickets with other statuses
    if (other > 0) {
      labels.push('Other')
      data.push(other)
    }
    
    return {
      labels,
      datasets: [
        {
          data,
          backgroundColor: [
            'rgba(231, 76, 60, 0.6)',   // Red for To Do
            'rgba(241, 196, 15, 0.6)',  // Yellow for In Progress  
            'rgba(46, 204, 113, 0.6)',  // Green for Done
            'rgba(155, 89, 182, 0.6)',  // Purple for Other
          ],
          borderColor: [
            'rgba(231, 76, 60, 1)',
            'rgba(241, 196, 15, 1)',
            'rgba(46, 204, 113, 1)',
            'rgba(155, 89, 182, 1)',
          ],
          borderWidth: 1,
        },
      ],
    }
  }

  const getCompletedTicketsData = () => {
    if (!dashboardData?.charts_data?.tickets?.developer_completed) {
      return {
        labels: ['Loading...'],
        datasets: [{ label: 'Completed Tickets', data: [0], backgroundColor: 'rgba(46, 204, 113, 0.6)' }]
      }
    }
    
    const developerCompleted = dashboardData.charts_data.tickets.developer_completed
    const labels = Object.keys(developerCompleted)
    const data = Object.values(developerCompleted)
    
    return {
      labels,
      datasets: [
        {
          label: 'Completed Tickets',
          data,
          backgroundColor: 'rgba(46, 204, 113, 0.6)',
          borderColor: 'rgba(46, 204, 113, 1)',
          borderWidth: 1,
        },
      ],
    }
  }

  const chartOptions = {
    responsive: true,
    plugins: {
      legend: {
        position: 'top',
      },
    },
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
            <p>Development & Project Analytics</p>
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
          
          {/* Two Bar Charts Side by Side */}
          <div className="charts-grid-two">
            <div className="chart-container">
              <h3>Commit Activity by Developer</h3>
              <div className="chart-with-legend">
                <Bar data={getCommitsChartData()} options={{
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: {
                    legend: {
                      position: 'bottom',
                      labels: {
                        padding: 8,
                        usePointStyle: true,
                        font: {
                          size: 10
                        },
                        boxWidth: 12,
                        boxHeight: 12,
                      },
                      maxHeight: 80,
                    },
                    tooltip: {
                      callbacks: {
                        title: function(context) {
                          return context[0].label; // Show the week/time period
                        },
                        label: function(context) {
                          const developerName = context.dataset.label.split(' (')[0]; // Remove total from tooltip
                          return `${developerName}: ${context.parsed.y} commits`;
                        }
                      }
                    }
                  },
                  scales: {
                    x: {
                      stacked: true,
                      ticks: {
                        font: {
                          size: 10
                        }
                      }
                    },
                    y: {
                      stacked: true,
                      ticks: {
                        font: {
                          size: 10
                        }
                      }
                    },
                  }
                }} />
              </div>
            </div>
            
            <div className="chart-container">
              <h3>Completed Tickets by Developer</h3>
              <div className="chart-with-legend">
                <Bar data={getCompletedTicketsData()} options={{
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: {
                    legend: {
                      position: 'bottom',
                      labels: {
                        padding: 8,
                        usePointStyle: true,
                        font: {
                          size: 10
                        },
                        boxWidth: 12,
                        boxHeight: 12,
                      },
                      maxHeight: 60,
                    },
                  },
                  scales: {
                    x: {
                      ticks: {
                        maxRotation: 45,
                        minRotation: 0,
                        font: {
                          size: 10
                        },
                        callback: function(value, index, values) {
                          const label = this.getLabelForValue(value);
                          // Truncate long names
                          return label.length > 12 ? label.substring(0, 12) + '...' : label;
                        }
                      }
                    },
                    y: {
                      ticks: {
                        font: {
                          size: 10
                        }
                      }
                    }
                  }
                }} />
              </div>
            </div>
          </div>

          {/* Two Pie Charts Side by Side */}
          <div className="charts-grid-two">
            <div className="chart-container pie-chart-container">
              <h3>Pull Request Status</h3>
              <div className="pie-chart-wrapper">
                <Doughnut data={getPRStatusData()} options={{
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: {
                    legend: {
                      position: 'bottom',
                      labels: {
                        padding: 10,
                        font: {
                          size: 11
                        },
                        boxWidth: 12,
                        boxHeight: 12,
                        usePointStyle: true
                      },
                      maxHeight: 60,
                    },
                  }
                }} />
              </div>
            </div>
            
            <div className="chart-container pie-chart-container">
              <h3>Jira Ticket Status</h3>
              <div className="pie-chart-wrapper">
                <Doughnut data={getTicketStatusData()} options={{
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: {
                    legend: {
                      position: 'bottom',
                      labels: {
                        padding: 10,
                        font: {
                          size: 11
                        },
                        boxWidth: 12,
                        boxHeight: 12,
                        usePointStyle: true
                      },
                      maxHeight: 60,
                    },
                  }
                }} />
              </div>
            </div>
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
