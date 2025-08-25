class DashboardController < ApplicationController
  include AiQueryProcessor

  skip_before_action :verify_authenticity_token, only: [ :ai_query ]

  def index
    # Renders the main React app
  end

  def api_data
    timeframe = params[:timeframe] || "24h"
    app_type = params[:app_type] || "legacy"
    timeframe_start = calculate_timeframe_start(timeframe)

    # Extend with the appropriate analytics module
    extend get_analytics_module(app_type)

    render json: {
      timeframe: timeframe,
      app_type: app_type,
      message: "Dashboard API is working!",
      charts_data: {
        commits: get_commits_data(timeframe_start, timeframe),
        pull_requests: get_pull_requests_data(timeframe_start),
        tickets: get_tickets_data(timeframe_start),
        # Additional chart data
        activity_timeline: get_activity_timeline_data(timeframe_start, timeframe),
        commits_per_repository: get_commits_per_repository_data(timeframe_start),
        ticket_priority_distribution: get_ticket_priority_distribution_data(timeframe_start),
        language_distribution: get_language_distribution_data(timeframe_start),
        # NEW: Additional metrics
        pull_request_activity_by_developer: get_pull_request_activity_by_developer_data(timeframe_start),
        ticket_type_completion: get_ticket_type_completion_data(timeframe_start)
      },
      summary: get_summary_data(timeframe_start, app_type),
      developer_stats: get_developer_stats(timeframe_start),
      repo_stats: get_repository_stats(timeframe_start)
    }
  end

  # AI Query endpoint
  def ai_query
    user_query = params[:query]
    app_type = params[:app_type] || "legacy"

    if user_query.blank?
      render json: { error: "Query cannot be empty" }, status: 400
      return
    end

    result = process_ai_query(user_query, app_type)

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

  def get_analytics_module(app_type)
    case app_type
    when "pioneer"
      PioneerAnalytics
    else
      LegacyAnalytics
    end
  end

  def get_summary_data(timeframe_start, app_type)
    {
      total_repositories: Repository.where(app_type: app_type).count,
      total_developers: Developer.where(app_type: app_type).count,
      total_commits: Commit.where(app_type: app_type).where("committed_at >= ?", timeframe_start).count,
      total_pull_requests: PullRequest.where(app_type: app_type).where("opened_at >= ?", timeframe_start).count,
      total_tickets: Ticket.where(app_type: app_type).where("created_at_jira >= ?", timeframe_start).count
    }
  end

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
