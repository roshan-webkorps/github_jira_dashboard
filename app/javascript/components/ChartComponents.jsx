// ChartComponents.jsx - Individual chart components with improved legend handling
import React from 'react'
import { Bar, Doughnut, Line, Bubble } from 'react-chartjs-2'
import {
  getCommitsChartData,
  getActivityTimelineData,
  getCommitsPerRepositoryData,
  getTicketPriorityData,
  getLanguageDistributionData,
  getPRStatusData,
  getTicketStatusData,
  getCompletedTicketsData,
  getPullRequestActivityData,
  getTicketTypeCompletionData,
  getCodeImpactData,
  getCodeChangesByDeveloperAndRepoData,
  getChangeEfficiencyData
} from './ChartDataHelpers'

const barChartOptions = {
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
}

const stackedBarChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      position: 'bottom',
      labels: {
        padding: 4,
        usePointStyle: true,
        font: {
          size: 9
        },
        boxWidth: 10,
        boxHeight: 10,
      },
      maxHeight: 80, // Reduced to prevent cutoff
    },
    tooltip: {
      callbacks: {
        title: function(context) {
          return context[0].label;
        },
        label: function(context) {
          const developerName = context.dataset.label.split(' (')[0];
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
}

const lineChartOptions = {
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
  },
  scales: {
    x: {
      ticks: {
        font: {
          size: 10
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
}

const pieChartOptions = {
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
}

const bubbleChartOptions = {
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
    tooltip: {
      callbacks: {
        title: function(context) {
          return context[0].raw.developer;
        },
        label: function(context) {
          const point = context.raw;
          return [
            `Commits: ${point.x}`,
            `Avg Lines/Commit: ${point.y}`,
            `Repositories: ${Math.round(point.r / 3)}`
          ];
        }
      }
    }
  },
  scales: {
    x: {
      title: {
        display: true,
        text: 'Total Commits'
      },
      ticks: {
        font: {
          size: 10
        }
      }
    },
    y: {
      title: {
        display: true,
        text: 'Avg Lines Changed per Commit'
      },
      ticks: {
        font: {
          size: 10
        }
      }
    }
  }
}

export const CodeImpactChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Number of Lines Added/Removed by Developer</h3>
    <div className="chart-with-legend">
      <Bar data={getCodeImpactData(dashboardData)} options={barChartOptions} />
    </div>
  </div>
)

export const CodeChangesByDeveloperAndRepoChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Code Changes by Developer & Repository</h3>
    <div className="chart-with-legend">
      <Bar 
        data={getCodeChangesByDeveloperAndRepoData(dashboardData)} 
        options={{
          ...stackedBarChartOptions,
          plugins: {
            ...stackedBarChartOptions.plugins,
            tooltip: {
              callbacks: {
                title: function(context) {
                  return context[0].label;
                },
                label: function(context) {
                  const repoName = context.dataset.label;
                  return `${repoName}: ${context.parsed.y} lines changed`;
                }
              }
            }
          }
        }} 
      />
    </div>
  </div>
)

export const CommitActivityChart = ({ dashboardData }) => {
  const totalDevelopers = dashboardData?.charts_data?.commits?.datasets 
    ? Object.keys(dashboardData.charts_data.commits.datasets).length 
    : 0;

  return (
    <div className="chart-container">
      <h3>Commit Activity by Developer</h3>
      {totalDevelopers > 10 && (
        <p className="chart-note">
          Showing top 10 developers by total commits ({totalDevelopers} total developers)
        </p>
      )}
      <div className="chart-with-legend">
        <Bar data={getCommitsChartData(dashboardData)} options={stackedBarChartOptions} />
      </div>
    </div>
  )
}

export const CompletedTicketsChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Completed Tickets by Developer</h3>
    <div className="chart-with-legend">
      <Bar data={getCompletedTicketsData(dashboardData)} options={{
        ...barChartOptions,
        scales: {
          ...barChartOptions.scales,
          x: {
            ticks: {
              maxRotation: 45,
              minRotation: 0,
              font: {
                size: 10
              },
              callback: function(value, index, values) {
                const label = this.getLabelForValue(value);
                return label.length > 12 ? label.substring(0, 12) + '...' : label;
              }
            }
          }
        }
      }} />
    </div>
  </div>
)

export const PullRequestStatusChart = ({ dashboardData }) => (
  <div className="chart-container pie-chart-container">
    <h3>Pull Request Status</h3>
    <div className="pie-chart-wrapper">
      <Doughnut data={getPRStatusData(dashboardData)} options={pieChartOptions} />
    </div>
  </div>
)

export const JiraTicketStatusChart = ({ dashboardData }) => (
  <div className="chart-container pie-chart-container">
    <h3>Jira Ticket Status</h3>
    <div className="pie-chart-wrapper">
      <Doughnut data={getTicketStatusData(dashboardData)} options={pieChartOptions} />
    </div>
  </div>
)

export const ActivityTimelineChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Activity Timeline</h3>
    <div className="chart-with-legend">
      <Line data={getActivityTimelineData(dashboardData)} options={lineChartOptions} />
    </div>
  </div>
)

export const CommitsPerRepositoryChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Commits per Repository</h3>
    <div className="chart-with-legend">
      <Bar data={getCommitsPerRepositoryData(dashboardData)} options={barChartOptions} />
    </div>
  </div>
)

export const TicketPriorityChart = ({ dashboardData }) => (
  <div className="chart-container pie-chart-container">
    <h3>Ticket Priority Distribution</h3>
    <div className="pie-chart-wrapper">
      <Doughnut data={getTicketPriorityData(dashboardData)} options={pieChartOptions} />
    </div>
  </div>
)

export const LanguageDistributionChart = ({ dashboardData }) => (
  <div className="chart-container pie-chart-container">
    <h3>Language Distribution</h3>
    <div className="pie-chart-wrapper">
      <Doughnut data={getLanguageDistributionData(dashboardData)} options={pieChartOptions} />
    </div>
  </div>
)

export const PullRequestActivityChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Pull Request Activity by Developer</h3>
    <div className="chart-with-legend">
      <Bar data={getPullRequestActivityData(dashboardData)} options={barChartOptions} />
    </div>
  </div>
)

export const TicketTypeCompletionChart = ({ dashboardData }) => (
  <div className="chart-container">
    <h3>Ticket Type Completion</h3>
    <div className="chart-with-legend">
      <Bar data={getTicketTypeCompletionData(dashboardData)} options={barChartOptions} />
    </div>
  </div>
)
