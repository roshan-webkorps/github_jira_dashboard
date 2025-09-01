class DashboardController < ApplicationController
  include BedrockAiQueryProcessor

  skip_before_action :verify_authenticity_token, only: [ :ai_query, :reset_chat ]

  # Store chat services in session to maintain context during user session
  before_action :initialize_chat_service, only: [ :ai_query, :reset_chat ]

  def index
    # Renders the main React app
  end

  def api_data
    session.delete(:chat_service) if request.get? && request.path == "/api/dashboard"

    timeframe = params[:timeframe] || "24h"
    app_type = params[:app_type] || "pioneer"
    timeframe_start = calculate_timeframe_start(timeframe)

    # Extend with the appropriate analytics module
    extend get_analytics_module(app_type)

    # Base charts that both app types have
    base_charts = {
      commits: get_commits_data(timeframe_start, timeframe),
      pull_requests: get_pull_requests_data(timeframe_start),
      tickets: get_tickets_data(timeframe_start),
      activity_timeline: get_activity_timeline_data(timeframe_start, timeframe),
      commits_per_repository: get_commits_per_repository_data(timeframe_start),
      ticket_priority_distribution: get_ticket_priority_distribution_data(timeframe_start),
      pull_request_activity_by_developer: get_pull_request_activity_by_developer_data(timeframe_start),
      ticket_type_completion: get_ticket_type_completion_data(timeframe_start)
    }

    # Conditional charts based on app_type
    if app_type == "legacy"
      # Legacy gets code impact charts instead of language distribution and PR status
      base_charts.merge!({
        code_impact_by_developer: get_code_impact_by_developer_data(timeframe_start),
        code_changes_by_developer_and_repo: get_code_changes_by_developer_and_repo_data(timeframe_start)
      })
    else
      # Pioneer gets the original charts
      base_charts.merge!({
        language_distribution: get_language_distribution_data(timeframe_start)
        # You can add PR status back if needed: pull_request_status: get_pr_status_data(timeframe_start)
      })
    end

    render json: {
      timeframe: timeframe,
      app_type: app_type,
      message: "Dashboard API is working!",
      charts_data: base_charts,
      summary: get_summary_data(timeframe_start, app_type),
      developer_stats: get_developer_stats(timeframe_start),
      repo_stats: get_repository_stats(timeframe_start)
    }
  end

  # AI Query endpoint
  def ai_query
    user_query = params[:query]
    app_type = params[:app_type] || "pioneer"

    if user_query.blank?
      render json: { error: "Query cannot be empty" }, status: 400
      return
    end

    begin
      # Process query with chat context using the updated processor
      result = process_bedrock_ai_query(user_query, app_type, @chat_service)

      render json: result
    rescue => e
      Rails.logger.error "AI Query Error: #{e.message}"
      render json: {
        error: "Sorry, I couldn't process your query. Please try rephrasing it."
      }, status: 500
    end
  end

  # New endpoint for resetting chat context
  def reset_chat
    # Clear chat context for new topic
    session.delete(:chat_service)  # Change this line
    @chat_service = Ai::ChatService.new
    # Don't serialize back to session immediately - let it be empty

    render json: { success: true, message: "Chat context reset" }
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

  def chat_status
    has_context = session[:chat_service].present? && !session[:chat_service].empty?
    render json: { has_context: has_context }
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

  # Chat service management methods
  def initialize_chat_service
    if session[:chat_service] && !session[:chat_service].empty?  # Add empty check
      @chat_service = deserialize_chat_service(session[:chat_service])
    else
      @chat_service = Ai::ChatService.new
    end
  rescue => e
    Rails.logger.error "Chat service initialization error: #{e.message}"
    @chat_service = Ai::ChatService.new
  end

  # Simple serialization for session storage
  def serialize_chat_service(chat_service)
    # Store all context types but limit size
    context = chat_service.data_context || {}
    {
      developers: (context[:developers] || context["developers"] || []).first(3),
      repositories: (context[:repositories] || context["repositories"] || []).first(3),
      tickets: (context[:tickets] || context["tickets"] || []).first(3),
      pull_requests: (context[:pull_requests] || context["pull_requests"] || []).first(3)
    }.compact
  end

  def deserialize_chat_service(serialized_data)
    chat_service = Ai::ChatService.new
    if serialized_data&.any?
      chat_service.instance_variable_set(:@data_context, serialized_data.symbolize_keys)
    end
    chat_service
  end

  # Update session after processing
  after_action :update_chat_session, only: [ :ai_query ]

  def update_chat_session
    if @chat_service
      session[:chat_service] = serialize_chat_service(@chat_service)
    end
  end
end
