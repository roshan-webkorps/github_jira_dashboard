class DashboardController < ApplicationController
  def index
    # Renders the main React app
  end
  
  def api_data
    timeframe = params[:timeframe] || '24h'
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
        total_commits: Commit.where('committed_at >= ?', timeframe_start).count,
        total_pull_requests: PullRequest.where('opened_at >= ?', timeframe_start).count,
        total_tickets: Ticket.where('created_at_jira >= ?', timeframe_start).count
      },
      developer_stats: get_developer_stats(timeframe_start),
      repo_stats: get_repository_stats(timeframe_start)
    }
  end
  
  def health_check
    render json: {
      status: "ok",
      timestamp: Time.current,
      database: database_status,
      github_token: ENV['GITHUB_TOKEN'].present? ? "configured" : "missing"
    }
  end
  
  private
  
  def calculate_timeframe_start(timeframe)
    case timeframe
    when '24h'
      24.hours.ago
    when '7d'
      7.days.ago
    when '1m'
      1.month.ago
    when '6m'
      6.months.ago
    when '1y'
      1.year.ago
    else
      24.hours.ago
    end
  end
  
  def get_commits_data(since, timeframe)
    commits = Commit.includes(:developer, :repository)
                    .where('committed_at >= ?', since)
                    .order(:committed_at)
    
    if commits.empty?
      return sample_commits_data(timeframe)
    end
    
    # Group commits by time periods based on timeframe
    case timeframe
    when '24h'
      group_commits_by_hours(commits, since)
    when '7d'
      group_commits_by_days(commits, since)
    when '1m'
      group_commits_by_weeks(commits, since)
    when '6m'
      group_commits_by_months(commits, since)
    when '1y'
      group_commits_by_quarters(commits, since)
    else
      group_commits_by_days(commits, since)
    end
  end
  
  def get_pull_requests_data(since)
    prs = PullRequest.where('opened_at >= ?', since)
    
    if prs.empty?
      return { open: 0, merged: 0, closed: 0 }
    end
    
    {
      open: prs.where(state: 'open').count,
      merged: prs.where.not(merged_at: nil).count,
      closed: prs.where(state: 'closed', merged_at: nil).count
    }
  end
  
  def group_commits_by_hours(commits, since)
    labels = []
    data = []
    
    (0..23).each do |hour|
      time = since + hour.hours
      label = "#{hour}h ago"
      count = commits.select { |c| c.committed_at >= time && c.committed_at < time + 1.hour }.count
      
      labels << label
      data << count
    end
    
    { labels: labels.reverse, data: data.reverse }
  end
  
  def group_commits_by_days(commits, since)
    labels = []
    data = []
    
    (0..6).each do |day|
      date = since + day.days
      label = date.strftime('%a')
      count = commits.select { |c| c.committed_at.to_date == date.to_date }.count
      
      labels << label
      data << count
    end
    
    { labels: labels, data: data }
  end
  
  def group_commits_by_weeks(commits, since)
    labels = []
    data = []
    
    4.times do |week|
      start_date = since + (week * 7).days
      end_date = start_date + 7.days
      label = "Week #{week + 1}"
      count = commits.select { |c| c.committed_at >= start_date && c.committed_at < end_date }.count
      
      labels << label
      data << count
    end
    
    { labels: labels, data: data }
  end
  
  def group_commits_by_months(commits, since)
    labels = []
    data = []
    
    6.times do |month|
      date = since + month.months
      label = date.strftime('%b')
      count = commits.select { |c| c.committed_at.month == date.month && c.committed_at.year == date.year }.count
      
      labels << label
      data << count
    end
    
    { labels: labels, data: data }
  end
  
  def group_commits_by_quarters(commits, since)
    labels = ['Q1', 'Q2', 'Q3', 'Q4']
    data = []
    
    (1..4).each do |quarter|
      start_month = (quarter - 1) * 3 + 1
      end_month = quarter * 3
      count = commits.select do |c|
        c.committed_at.month >= start_month && c.committed_at.month <= end_month
      end.count
      
      data << count
    end
    
    { labels: labels, data: data }
  end
  
  def get_tickets_data(since)
    tickets = Ticket.where('created_at_jira >= ?', since)
    
    if tickets.empty?
      return { todo: 0, in_progress: 0, done: 0 }
    end
    
    # Group by common status categories
    todo_statuses = ['To Do', 'Open', 'New', 'Backlog']
    in_progress_statuses = ['In Progress', 'In Review', 'Testing', 'Code Review']
    done_statuses = ['Done', 'Closed', 'Resolved', 'Complete']
    
    {
      todo: tickets.where(status: todo_statuses).count,
      in_progress: tickets.where(status: in_progress_statuses).count,
      done: tickets.where(status: done_statuses).count,
      other: tickets.where.not(status: todo_statuses + in_progress_statuses + done_statuses).count
    }
  end
  
  def get_repository_stats(since)
    Repository.joins(:commits)
              .where('commits.committed_at >= ?', since)
              .group('repositories.id', 'repositories.name')
              .order('COUNT(commits.id) DESC')
              .limit(10)
              .pluck('repositories.name', 'COUNT(commits.id)')
              .map { |name, count| { name: name, commits: count } }
  end
  
  def get_developer_stats(since)
    Developer.joins(:commits)
             .where('commits.committed_at >= ?', since)
             .group('developers.id', 'developers.name')
             .order('COUNT(commits.id) DESC')
             .limit(10)
             .pluck('developers.name', 'COUNT(commits.id)')
             .map { |name, count| { name: name, commits: count } }
  end
  
  def database_status
    ActiveRecord::Base.connection.execute("SELECT 1")
    "connected"
  rescue
    "disconnected"
  end
  
  # Fallback sample data when no real data exists
  def sample_commits_data(timeframe)
    case timeframe
    when '24h'
      { labels: ['6h ago', '12h ago', '18h ago', '24h ago'], data: [3, 7, 2, 5] }
    when '7d'
      { labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], data: [12, 19, 8, 15, 22, 10, 14] }
    when '1m'
      { labels: ['Week 1', 'Week 2', 'Week 3', 'Week 4'], data: [45, 52, 38, 61] }
    when '6m'
      { labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'], data: [180, 210, 165, 245, 190, 220] }
    when '1y'
      { labels: ['Q1', 'Q2', 'Q3', 'Q4'], data: [520, 680, 590, 750] }
    else
      { labels: ['Week 1', 'Week 2', 'Week 3', 'Week 4'], data: [12, 19, 8, 15] }
    end
  end
end
