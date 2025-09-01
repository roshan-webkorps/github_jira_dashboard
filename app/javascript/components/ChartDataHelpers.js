// ChartDataHelpers.js - Handles all chart data transformations

export const getCommitsChartData = (dashboardData) => {
  if (!dashboardData?.charts_data?.commits) {
    return {
      labels: ['Loading...'],
      datasets: [{ label: 'Commits', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' }]
    }
  }
  
  const { labels, datasets } = dashboardData.charts_data.commits
  
  const chartDatasets = []
  
  // Extended color palette for 10 developers
  const colors = [
    'rgba(52, 152, 219, 0.6)',   // Blue
    'rgba(46, 204, 113, 0.6)',   // Green  
    'rgba(241, 196, 15, 0.6)',   // Yellow
    'rgba(231, 76, 60, 0.6)',    // Red
    'rgba(155, 89, 182, 0.6)',   // Purple
    'rgba(230, 126, 34, 0.6)',   // Orange
    'rgba(26, 188, 156, 0.6)',   // Turquoise
    'rgba(52, 73, 94, 0.6)',     // Dark Gray
    'rgba(22, 160, 133, 0.6)',   // Green Sea
    'rgba(39, 174, 96, 0.6)',    // Emerald
  ]
  
  let colorIndex = 0
  
  // Sort developers by total commits (descending) and limit to top 10
  const sortedDevelopers = Object.entries(datasets)
    .map(([name, data]) => ({ name, data, total: data.reduce((sum, count) => sum + count, 0) }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 10) // Show top 10 developers with most commits
  
  sortedDevelopers.forEach(({ name, data, total }) => {
    // Only include developers with at least 1 commit to avoid clutter
    if (total > 0) {
      const displayName = name.length > 15 ? name.substring(0, 15) + '...' : name
      
      chartDatasets.push({
        label: `${displayName} (${total})`,
        data: data,
        backgroundColor: colors[colorIndex % colors.length],
        borderColor: colors[colorIndex % colors.length].replace('0.6', '1').replace('0.4', '1'),
        borderWidth: 1,
      })
      colorIndex++
    }
  })
  
  return { labels, datasets: chartDatasets }
}

export const getActivityTimelineData = (dashboardData) => {
  if (!dashboardData?.charts_data?.activity_timeline) {
    return {
      labels: ['Loading...'],
      datasets: [
        { label: 'Commits', data: [0], borderColor: 'rgba(52, 152, 219, 1)', backgroundColor: 'rgba(52, 152, 219, 0.1)' },
        { label: 'Completed Tickets', data: [0], borderColor: 'rgba(46, 204, 113, 1)', backgroundColor: 'rgba(46, 204, 113, 0.1)' }
      ]
    }
  }
  
  const { labels, commit_data, ticket_data } = dashboardData.charts_data.activity_timeline
  
  return {
    labels,
    datasets: [
      {
        label: 'Commits',
        data: commit_data,
        borderColor: 'rgba(52, 152, 219, 1)',
        backgroundColor: 'rgba(52, 152, 219, 0.1)',
        borderWidth: 2,
        fill: true,
        tension: 0.4
      },
      {
        label: 'Completed Tickets',
        data: ticket_data,
        borderColor: 'rgba(46, 204, 113, 1)',
        backgroundColor: 'rgba(46, 204, 113, 0.1)',
        borderWidth: 2,
        fill: true,
        tension: 0.4
      }
    ]
  }
}

export const getCommitsPerRepositoryData = (dashboardData) => {
  if (!dashboardData?.charts_data?.commits_per_repository) {
    return {
      labels: ['Loading...'],
      datasets: [{ label: 'Commits', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' }]
    }
  }
  
  return dashboardData.charts_data.commits_per_repository
}

export const getTicketPriorityData = (dashboardData) => {
  if (!dashboardData?.charts_data?.ticket_priority_distribution) {
    return {
      labels: ['Loading...'],
      datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
    }
  }
  
  return dashboardData.charts_data.ticket_priority_distribution
}

export const getLanguageDistributionData = (dashboardData) => {
  if (!dashboardData?.charts_data?.language_distribution) {
    return {
      labels: ['Loading...'],
      datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
    }
  }
  
  return dashboardData.charts_data.language_distribution
}

export const getPRStatusData = (dashboardData) => {
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

export const getTicketStatusData = (dashboardData) => {
  if (!dashboardData?.charts_data?.tickets?.totals) {
    return {
      labels: ['Loading...'],
      datasets: [{ data: [1], backgroundColor: ['rgba(52, 152, 219, 0.6)'] }]
    }
  }
  
  const { todo, in_progress, done, other } = dashboardData.charts_data.tickets.totals
  const labels = ['To Do', 'In Progress', 'Done']
  const data = [todo, in_progress, done]
  
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

export const getCompletedTicketsData = (dashboardData) => {
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

// NEW: Pull Request Activity by Developer
export const getPullRequestActivityData = (dashboardData) => {
  if (!dashboardData?.charts_data?.pull_request_activity_by_developer) {
    return {
      labels: ['Loading...'],
      datasets: [
        { label: 'PRs Created', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' },
        { label: 'PRs Closed/Merged', data: [0], backgroundColor: 'rgba(46, 204, 113, 0.6)' }
      ]
    }
  }
  
  return dashboardData.charts_data.pull_request_activity_by_developer
}

// NEW: Ticket Type Completion Data
export const getTicketTypeCompletionData = (dashboardData) => {
  if (!dashboardData?.charts_data?.ticket_type_completion) {
    return {
      labels: ['Loading...'],
      datasets: [{ label: 'Tickets', data: [0], backgroundColor: 'rgba(52, 152, 219, 0.6)' }]
    }
  }
  
  return dashboardData.charts_data.ticket_type_completion
}

export const getCodeImpactData = (dashboardData) => {
  if (!dashboardData?.charts_data?.code_impact_by_developer) {
    return {
      labels: ['Loading...'],
      datasets: [
        { label: 'Lines Added', data: [0], backgroundColor: 'rgba(46, 204, 113, 0.6)' },
        { label: 'Lines Deleted', data: [0], backgroundColor: 'rgba(231, 76, 60, 0.6)' }
      ]
    }
  }
  
  return dashboardData.charts_data.code_impact_by_developer
}

export const getChangeEfficiencyData = (dashboardData) => {
  if (!dashboardData?.charts_data?.change_efficiency) {
    return {
      datasets: [{ 
        label: 'Efficiency', 
        data: [{ x: 0, y: 0, r: 5 }], 
        backgroundColor: 'rgba(52, 152, 219, 0.6)' 
      }]
    }
  }
  
  return dashboardData.charts_data.change_efficiency
}

export const getCodeChangesByDeveloperAndRepoData = (dashboardData) => {
  if (!dashboardData?.charts_data?.code_changes_by_developer_and_repo) {
    return {
      labels: ['Loading...'],
      datasets: [{ 
        label: 'Lines Changed', 
        data: [0], 
        backgroundColor: 'rgba(52, 152, 219, 0.6)' 
      }]
    }
  }
  
  return dashboardData.charts_data.code_changes_by_developer_and_repo
}
