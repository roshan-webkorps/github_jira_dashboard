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

  const getCommitsChartData = () => {
    if (!dashboardData?.charts_data?.commits) {
      return {
        labels: ['Loading...'],
        datasets: [{ label: 'Commits', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' }]
      }
    }
    
    const { labels, data } = dashboardData.charts_data.commits
    return {
      labels,
      datasets: [
        {
          label: 'Commits',
          data,
          backgroundColor: 'rgba(52, 152, 219, 0.6)',
          borderColor: 'rgba(52, 152, 219, 1)',
          borderWidth: 1,
        },
      ],
    }
  }

  const getPRStatusData = () => {
    if (!dashboardData?.charts_data?.pull_requests) {
      return {
        labels: ['Loading...'],
        datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
      }
    }
    
    const { open, merged, closed } = dashboardData.charts_data.pull_requests
    return {
      labels: ['Open', 'Merged', 'Closed'],
      datasets: [
        {
          data: [open, merged, closed],
          backgroundColor: [
            'rgba(241, 196, 15, 0.6)',
            'rgba(46, 204, 113, 0.6)',
            'rgba(231, 76, 60, 0.6)',
          ],
          borderColor: [
            'rgba(241, 196, 15, 1)',
            'rgba(46, 204, 113, 1)',
            'rgba(231, 76, 60, 1)',
          ],
          borderWidth: 1,
        },
      ],
    }
  }

  const getTicketStatusData = () => {
    if (!dashboardData?.charts_data?.tickets) {
      return {
        labels: ['Loading...'],
        datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
      }
    }
    
    const { todo, in_progress, done, other } = dashboardData.charts_data.tickets
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
          <div className="charts-grid-three">
            <div className="chart-container">
              <h3>Commit Activity</h3>
              <Bar data={getCommitsChartData()} options={chartOptions} />
            </div>
            
            <div className="chart-container">
              <h3>Pull Request Status</h3>
              <Doughnut data={getPRStatusData()} options={chartOptions} />
            </div>
            
            <div className="chart-container">
              <h3>Jira Ticket Status</h3>
              <Doughnut data={getTicketStatusData()} options={chartOptions} />
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}

export default App
