module Analytics
  extend ActiveSupport::Concern

  private

  def get_commits_data(since, timeframe)
    commits = Commit.includes(:developer, :repository)
                    .where("committed_at >= ?", since)
                    .order(:committed_at)

    # Group commits by developer and time periods
    case timeframe
    when "24h"
      group_commits_by_developers_and_hours(commits, since)
    when "7d"
      group_commits_by_developers_and_days(commits, since)
    when "1m"
      group_commits_by_developers_and_weeks(commits, since)
    when "6m"
      group_commits_by_developers_and_months(commits, since)
    when "1y"
      group_commits_by_developers_and_quarters(commits, since)
    else
      group_commits_by_developers_and_days(commits, since)
    end
  end

  def get_pull_requests_data(since)
    prs = PullRequest.includes(:developer)
                     .where("opened_at >= ?", since)

    if prs.empty?
      return { developers: {}, totals: { open: 0, closed_merged: 0 } }
    end

    # Group PRs by developer and simplified status (open vs closed/merged)
    developer_data = {}

    # Get all developers who have PRs
    developer_names = prs.joins(:developer).pluck("developers.name").uniq

    developer_names.each do |dev_name|
      dev_prs = prs.joins(:developer).where("developers.name = ?", dev_name)

      developer_data[dev_name] = {
        open: dev_prs.where(state: "open").count,
        closed_merged: dev_prs.where(state: "closed").count + dev_prs.where.not(merged_at: nil).count
      }
    end

    # Calculate totals
    totals = { open: 0, closed_merged: 0 }
    developer_data.each do |_, dev_stats|
      totals[:open] += dev_stats[:open]
      totals[:closed_merged] += dev_stats[:closed_merged]
    end

    { developers: developer_data, totals: totals }
  end

  def get_tickets_data(since)
    tickets = Ticket.includes(:developer)
                    .where("created_at_jira >= ?", since)

    if tickets.empty?
      return { developers: {}, totals: { todo: 0, in_progress: 0, done: 0, other: 0 }, developer_completed: {} }
    end

    # Group tickets by developer and status
    todo_statuses = [ "To Do", "Open", "New", "Backlog" ]
    in_progress_statuses = [ "In Progress", "In Review", "Testing", "Code Review" ]
    done_statuses = [ "Done", "Closed", "Resolved", "Complete", "Deployed" ]

    developer_data = {}
    developer_completed = {}

    tickets.joins(:developer).group("developers.name", :status).count.each do |(dev_name, status), count|
      developer_data[dev_name] ||= { todo: 0, in_progress: 0, done: 0, other: 0 }

      if todo_statuses.include?(status)
        developer_data[dev_name][:todo] += count
      elsif in_progress_statuses.include?(status)
        developer_data[dev_name][:in_progress] += count
      elsif done_statuses.include?(status)
        developer_data[dev_name][:done] += count
        developer_completed[dev_name] = (developer_completed[dev_name] || 0) + count
      else
        developer_data[dev_name][:other] += count
      end
    end

    # Calculate totals
    totals = { todo: 0, in_progress: 0, done: 0, other: 0 }
    developer_data.each do |_, dev_stats|
      totals[:todo] += dev_stats[:todo]
      totals[:in_progress] += dev_stats[:in_progress]
      totals[:done] += dev_stats[:done]
      totals[:other] += dev_stats[:other]
    end

    { developers: developer_data, totals: totals, developer_completed: developer_completed }
  end

  def group_commits_by_developers_and_days(commits, since)
    labels = []
    developer_datasets = {}

    (6.downto(0)).each do |days_ago|
      date = Date.current - days_ago.days
      labels << date.strftime("%a")
    end

    # Initialize datasets for each developer
    developer_names = commits.joins(:developer).pluck("developers.name").uniq
    developer_names.each do |name|
      developer_datasets[name] = Array.new(7, 0)
    end

    # Count commits by developer and day
    commits.each do |commit|
      commit_date = commit.committed_at.to_date
      days_ago = (Date.current - commit_date).to_i

      # Map days_ago to array index (0 = 6 days ago, 6 = today)
      day_index = 6 - days_ago

      if day_index >= 0 && day_index < 7 && commit.developer
        developer_datasets[commit.developer.name][day_index] += 1
      end
    end

    { labels: labels, datasets: developer_datasets }
  end

  def group_commits_by_developers_and_weeks(commits, since)
    labels = []
    developer_datasets = {}

    # Get time labels
    4.times do |week|
      labels << "Week #{week + 1}"
    end

    # Initialize datasets for each developer
    developer_names = commits.joins(:developer).pluck("developers.name").uniq
    developer_names.each do |name|
      developer_datasets[name] = Array.new(4, 0)
    end

    # Count commits by developer and week
    commits.each do |commit|
      week_index = ((commit.committed_at - since) / 1.week).to_i
      if week_index >= 0 && week_index < 4 && commit.developer
        developer_datasets[commit.developer.name][week_index] += 1
      end
    end

    { labels: labels, datasets: developer_datasets }
  end

  def group_commits_by_developers_and_months(commits, since)
    labels = []
    developer_datasets = {}

    # Get time labels
    6.times do |month|
      date = since + month.months
      labels << date.strftime("%b")
    end

    # Initialize datasets for each developer
    developer_names = commits.joins(:developer).pluck("developers.name").uniq
    developer_names.each do |name|
      developer_datasets[name] = Array.new(6, 0)
    end

    # Count commits by developer and month
    commits.each do |commit|
      month_diff = ((commit.committed_at.year - since.year) * 12 + commit.committed_at.month - since.month)
      if month_diff >= 0 && month_diff < 6 && commit.developer
        developer_datasets[commit.developer.name][month_diff] += 1
      end
    end

    { labels: labels, datasets: developer_datasets }
  end

  def group_commits_by_developers_and_quarters(commits, since)
    labels = [ "Q1", "Q2", "Q3", "Q4" ]
    developer_datasets = {}

    # Initialize datasets for each developer
    developer_names = commits.joins(:developer).pluck("developers.name").uniq
    developer_names.each do |name|
      developer_datasets[name] = Array.new(4, 0)
    end

    # Count commits by developer and quarter
    commits.each do |commit|
      quarter = ((commit.committed_at.month - 1) / 3).to_i
      if quarter >= 0 && quarter < 4 && commit.developer
        developer_datasets[commit.developer.name][quarter] += 1
      end
    end

    { labels: labels, datasets: developer_datasets }
  end

  def group_commits_by_developers_and_hours(commits, since)
    labels = []
    developer_datasets = {}

    # Get time labels
    (0..23).each do |hour|
      labels << "#{hour}h ago"
    end

    # Initialize datasets for each developer
    developer_names = commits.joins(:developer).pluck("developers.name").uniq
    developer_names.each do |name|
      developer_datasets[name] = Array.new(24, 0)
    end

    # Count commits by developer and hour
    commits.each do |commit|
      hour_diff = ((Time.current - commit.committed_at) / 1.hour).to_i
      if hour_diff >= 0 && hour_diff < 24 && commit.developer
        developer_datasets[commit.developer.name][hour_diff] += 1
      end
    end

    { labels: labels.reverse, datasets: developer_datasets.transform_values(&:reverse) }
  end

  def get_repository_stats(since)
    Repository.joins(:commits)
              .where("commits.committed_at >= ?", since)
              .group("repositories.id", "repositories.name")
              .order("COUNT(commits.id) DESC")
              .limit(10)
              .pluck("repositories.name", "COUNT(commits.id)")
              .map { |name, count| { name: name, commits: count } }
  end

  def get_developer_stats(since)
    Developer.joins(:commits)
             .where("commits.committed_at >= ?", since)
             .group("developers.id", "developers.name")
             .order("COUNT(commits.id) DESC")
             .limit(10)
             .pluck("developers.name", "COUNT(commits.id)")
             .map { |name, count| { name: name, commits: count } }
  end
end
