class DashboardController < ApplicationController
  def index
    # Renders the main React app
  end

  def api_data
    render json: {
      developers_count: Developer.count,
      repositories_count: Repository.count,
      commits_count: Commit.count,
      pull_requests_count: PullRequest.count,
      tickets_count: Ticket.count,
      message: "Dashboard API is working!"
    }
  end

  def health_check
    render json: {
      status: "ok",
      timestamp: Time.current,
      database: database_status
    }
  end

  private

  def database_status
    ActiveRecord::Base.connection.execute("SELECT 1")
    "connected"
  rescue
    "disconnected"
  end
end
