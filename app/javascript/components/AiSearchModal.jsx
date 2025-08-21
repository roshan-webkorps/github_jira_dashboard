import React from 'react'
import { Bar, Doughnut } from 'react-chartjs-2'

const AiSearchModal = ({ isOpen, onClose, result, loading, error }) => {
  if (!isOpen) return null

  const renderChart = () => {
    if (!result || !result.data) return null

    const chartOptions = {
      responsive: true,
      plugins: {
        legend: {
          position: 'top',
        },
      },
    }

    switch (result.chart_type) {
      case 'bar':
        return (
          <div className="chart-container-modal">
            <Bar data={result.data} options={chartOptions} />
          </div>
        )
      case 'pie':
        return (
          <div className="chart-container-modal">
            <Doughnut data={result.data} options={chartOptions} />
          </div>
        )
      case 'table':
      default:
        return renderTable()
    }
  }

  const renderTable = () => {
    if (!result || !result.data || !result.data.headers) return null

    return (
      <div className="table-container">
        <table className="results-table">
          <thead>
            <tr>
              {result.data.headers.map((header, index) => (
                <th key={index}>{header.replace('_', ' ').toUpperCase()}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {result.data.rows.map((row, index) => (
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

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <div className="modal-title-section">
            <h3>AI Query Results</h3>
            {result && result.user_query && (
              <div className="user-query-display">
                <span className="query-label">Query:</span>
                <span className="query-text">"{result.user_query}"</span>
              </div>
            )}
          </div>
          <button className="modal-close" onClick={onClose}>×</button>
        </div>
        
        <div className="modal-body">
          {loading && (
            <div className="loading-state">
              <div className="spinner"></div>
              <p>Analyzing your query...</p>
            </div>
          )}
          
          {error && (
            <div className="error-state">
              <p className="error-message">❌ {error}</p>
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
          )}
          
          {result && !loading && !error && (
            <>
              <div className="result-content">
                {renderChart()}
              </div>
              
              {result.raw_results && result.raw_results.length > 0 && (
                <div className="result-summary">
                  <p className="result-count">
                    Found {result.raw_results.length} result{result.raw_results.length !== 1 ? 's' : ''}
                  </p>
                </div>
              )}
            </>
          )}
        </div>
        
        <div className="modal-footer">
          <button className="btn-secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  )
}

export default AiSearchModal
