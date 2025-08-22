class DashboardController < ApplicationController
  include Analytics
  include AiQueryProcessor

  skip_before_action :verify_authenticity_token, only: [ :ai_query ]

  def index
    # Renders the main React app
  end

  def api_data
    timeframe = params[:timeframe] || "24h"
    timeframe_start = calculate_timeframe_start(timeframe)

    render json: {
      timeframe: timeframe,
      message: "Dashboard API is working!",
      charts_data: {
        commits: get_commits_data(timeframe_start, timeframe),
        pull_requests: get_pull_requests_data(timeframe_start),
        tickets: get_tickets_data(timeframe_start)
      },
      summary: {
        total_repositories: Repository.count,
        total_developers: Developer.count,
        total_commits: Commit.where("committed_at >= ?", timeframe_start).count,
        total_pull_requests: PullRequest.where("opened_at >= ?", timeframe_start).count,
        total_tickets: Ticket.where("created_at_jira >= ?", timeframe_start).count
      },
      developer_stats: get_developer_stats(timeframe_start),
      repo_stats: get_repository_stats(timeframe_start)
    }
  end

  # NEW: AI Query endpoint
  def ai_query
    user_query = params[:query]

    if user_query.blank?
      render json: { error: "Query cannot be empty" }, status: 400
      return
    end

    result = process_ai_query(user_query)

    if result[:error]
      render json: result, status: 400
    else
      render json: result
    end
  end

  def health_check
    render json: {
      status: "ok",
      timestamp: Time.current,
      database: database_status,
      github_token: ENV["GITHUB_TOKEN"].present? ? "configured" : "missing",
      openai_token: ENV["OPENAI_API_KEY"].present? ? "configured" : "missing"
    }
  end

  private

  def calculate_timeframe_start(timeframe)
    case timeframe
    when "24h"
      24.hours.ago
    when "7d"
      7.days.ago
    when "1m"
      1.month.ago
    when "6m"
      6.months.ago
    when "1y"
      1.year.ago
    else
      24.hours.ago
    end
  end

  def database_status
    ActiveRecord::Base.connection.execute("SELECT 1")
    "connected"
  rescue
    "disconnected"
  end
end
