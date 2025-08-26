module BaseAnalytics
  extend ActiveSupport::Concern

  private

  # Abstract method - must be implemented by subclasses
  def app_type
    raise NotImplementedError, "Subclasses must implement app_type method"
  end

  # Helper methods that automatically filter by app_type
  def scoped_commits
    Commit.where(app_type: app_type)
  end

  def scoped_pull_requests
    PullRequest.where(app_type: app_type)
  end

  def scoped_tickets
    Ticket.where(app_type: app_type)
  end

  def scoped_developers
    Developer.where(app_type: app_type)
  end

  def scoped_repositories
    Repository.where(app_type: app_type)
  end

  # All analytics methods using scoped collections
  def get_commits_data(since, timeframe)
    commits = scoped_commits.includes(:developer, :repository)
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
    prs = scoped_pull_requests.includes(:developer)
                             .where("pull_requests.opened_at >= ?", since)

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
    tickets = scoped_tickets.includes(:developer)
                           .where("updated_at_jira >= ?", since)

    if tickets.empty?
      return { developers: {}, totals: { todo: 0, in_progress: 0, done: 0, other: 0 }, developer_completed: {} }
    end

    # Group tickets by developer and status
    todo_statuses = [ "To Do", "Design To Do", "BLOCKED", "Blocked", "PUSHED BACK", "Pushed Back", "Need More Info", "No Response" ]
    in_progress_statuses = [ "In Progress", "Code Review", "READY FOR REVIEW", "Ready for Review", "TESTING", "Testing", "APPROVED BY QA", "Approved by QA", "PRODUCT CHECK", "Product Check", "FEEDBACK" ]
    done_statuses = [ "Done", "Deployed", "Deoployed To Demo", "Deployed To Demo", "Deployed to Demo", "Ready For Deploy", "Ready For Release", "Ready for Release" ]

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

  def get_activity_timeline_data(since, timeframe)
    commits = scoped_commits.where("committed_at >= ?", since).order(:committed_at)

    # Get completed tickets (using same done_statuses as existing method)
    done_statuses = [ "Done", "Closed", "Resolved", "Complete", "Deployed" ]
    completed_tickets = scoped_tickets.where("updated_at_jira >= ?", since)
                                     .where(status: done_statuses)
                                     .order(:updated_at_jira)

    case timeframe
    when "24h"
      group_activity_by_hours(commits, completed_tickets, since)
    when "7d"
      group_activity_by_days(commits, completed_tickets, since)
    when "1m"
      group_activity_by_weeks(commits, completed_tickets, since)
    when "6m"
      group_activity_by_months(commits, completed_tickets, since)
    when "1y"
      group_activity_by_quarters(commits, completed_tickets, since)
    else
      group_activity_by_days(commits, completed_tickets, since)
    end
  end

  def get_commits_per_repository_data(since)
    repo_commits = scoped_repositories.joins(:commits)
                                     .where("commits.committed_at >= ?", since)
                                     .group("repositories.name")
                                     .order("COUNT(commits.id) DESC")
                                     .limit(10)
                                     .count("commits.id")

    if repo_commits.empty?
      return { labels: [ "No Data" ], datasets: [ { label: "Commits", data: [ 0 ], backgroundColor: "rgba(52, 152, 219, 0.6)" } ] }
    end

    {
      labels: repo_commits.keys,
      datasets: [ {
        label: "Commits",
        data: repo_commits.values,
        backgroundColor: "rgba(52, 152, 219, 0.6)",
        borderColor: "rgba(52, 152, 219, 1)",
        borderWidth: 1
      } ]
    }
  end

  def get_ticket_priority_distribution_data(since)
    priority_counts = scoped_tickets.where("updated_at_jira >= ?", since)
                                   .group(:priority)
                                   .count

    if priority_counts.empty?
      return {
        labels: [ "No Data" ],
        datasets: [ { data: [ 1 ], backgroundColor: [ "rgba(52, 152, 219, 0.6)" ] } ]
      }
    end

    colors = [
      "rgba(231, 76, 60, 0.6)",   # Red for High
      "rgba(241, 196, 15, 0.6)",  # Yellow for Medium
      "rgba(46, 204, 113, 0.6)",  # Green for Low
      "rgba(155, 89, 182, 0.6)",  # Purple for other priorities
      "rgba(52, 152, 219, 0.6)",  # Blue
      "rgba(230, 126, 34, 0.6)"   # Orange
    ]

    border_colors = [
      "rgba(231, 76, 60, 1)",
      "rgba(241, 196, 15, 1)",
      "rgba(46, 204, 113, 1)",
      "rgba(155, 89, 182, 1)",
      "rgba(52, 152, 219, 1)",
      "rgba(230, 126, 34, 1)"
    ]

    {
      labels: priority_counts.keys.map { |p| p.present? ? p : "No Priority" },
      datasets: [ {
        data: priority_counts.values,
        backgroundColor: colors[0...priority_counts.size],
        borderColor: border_colors[0...priority_counts.size],
        borderWidth: 1
      } ]
    }
  end

  def get_language_distribution_data(since)
    # Get all repositories with their languages and total commit counts (not filtered by timeframe)
    language_data = scoped_repositories.joins(:commits)
                                      .where.not(language: [ nil, "" ])
                                      .group(:language, "repositories.name")
                                      .count("commits.id")
                                      .group_by { |((language, repo_name), count)| language }

    if language_data.empty?
      return {
        labels: [ "No Data" ],
        datasets: [ { data: [ 1 ], backgroundColor: [ "rgba(52, 152, 219, 0.6)" ] } ]
      }
    end

    # Calculate total commits per language and get top repositories for each
    language_stats = language_data.map do |language, repo_data|
      total_commits = repo_data.sum { |((lang, repo), count)| count }
      top_repo = repo_data.max_by { |((lang, repo), count)| count }
      top_repo_name = top_repo ? top_repo[0][1] : "Unknown"

      {
        language: language,
        commits: total_commits,
        top_repo: top_repo_name
      }
    end.sort_by { |stat| -stat[:commits] }.first(8)

    colors = [
      "rgba(52, 152, 219, 0.6)",   # Blue
      "rgba(46, 204, 113, 0.6)",   # Green
      "rgba(241, 196, 15, 0.6)",   # Yellow
      "rgba(231, 76, 60, 0.6)",    # Red
      "rgba(155, 89, 182, 0.6)",   # Purple
      "rgba(230, 126, 34, 0.6)",   # Orange
      "rgba(26, 188, 156, 0.6)",   # Turquoise
      "rgba(149, 165, 166, 0.6)"   # Gray
    ]

    border_colors = colors.map { |color| color.gsub("0.6", "1") }

    # Create labels that show both language and top repository
    labels = language_stats.map { |stat| "#{stat[:language]} (#{stat[:top_repo]})" }
    data = language_stats.map { |stat| stat[:commits] }

    {
      labels: labels,
      datasets: [ {
        data: data,
        backgroundColor: colors[0...language_stats.size],
        borderColor: border_colors[0...language_stats.size],
        borderWidth: 1
      } ]
    }
  end

  def get_pull_request_activity_by_developer_data(since)
    prs = scoped_pull_requests.includes(:developer)
                             .where("pull_requests.opened_at >= ?", since)

    if prs.empty?
      return {
        labels: [ "No Data" ],
        datasets: [
          { label: "Created", data: [ 0 ], backgroundColor: "rgba(52, 152, 219, 0.6)" },
          { label: "Closed/Merged", data: [ 0 ], backgroundColor: "rgba(46, 204, 113, 0.6)" }
        ]
      }
    end

    # Get all developers with their activity counts
    developer_activity = {}
    developer_names = prs.joins(:developer).pluck("developers.name").uniq

    developer_names.each do |dev_name|
      dev_prs = prs.joins(:developer).where("developers.name = ?", dev_name)

      created_count = dev_prs.count
      closed_count = dev_prs.where(state: "closed").count + dev_prs.where.not(merged_at: nil).count

      developer_activity[dev_name] = {
        created: created_count,
        closed: closed_count,
        total: created_count + closed_count
      }
    end

    # Sort developers by total activity (descending)
    sorted_developers = developer_activity.sort_by { |dev, data| -data[:total] }.to_h

    # Build the chart data
    labels = sorted_developers.keys.map { |name| name.length > 12 ? "#{name[0...9]}..." : name }
    created_data = sorted_developers.values.map { |data| data[:created] }
    closed_data = sorted_developers.values.map { |data| data[:closed] }

    {
      labels: labels,
      datasets: [
        {
          label: "PRs Created",
          data: created_data,
          backgroundColor: "rgba(52, 152, 219, 0.6)",
          borderColor: "rgba(52, 152, 219, 1)",
          borderWidth: 1
        },
        {
          label: "PRs Closed/Merged",
          data: closed_data,
          backgroundColor: "rgba(46, 204, 113, 0.6)",
          borderColor: "rgba(46, 204, 113, 1)",
          borderWidth: 1
        }
      ]
    }
  end

  def get_ticket_type_completion_data(since)
    tickets = scoped_tickets.includes(:developer)
                           .where("updated_at_jira >= ?", since)

    if tickets.empty?
      return {
        labels: [ "No Data" ],
        datasets: [ { label: "Tickets", data: [ 0 ], backgroundColor: "rgba(52, 152, 219, 0.6)" } ]
      }
    end

    # Use same done_statuses as existing get_tickets_data method
    done_statuses = [ "Done", "Closed", "Resolved", "Complete", "Deployed" ]

    # Filter to only completed tickets, same as get_tickets_data logic
    completed_tickets = tickets.where(status: done_statuses)

    if completed_tickets.empty?
      return {
        labels: [ "No Data" ],
        datasets: [ { label: "Tickets", data: [ 0 ], backgroundColor: "rgba(52, 152, 219, 0.6)" } ]
      }
    end

    # Group by priority/type and developer - same approach as existing method
    priority_developer_counts = {}
    developer_colors = {}

    # Use the same grouping logic as get_tickets_data
    completed_tickets.joins(:developer).group("developers.name", :priority).count.each do |(dev_name, priority), count|
      priority_key = priority.present? ? priority : "No Priority"

      priority_developer_counts[priority_key] ||= {}
      priority_developer_counts[priority_key][dev_name] ||= 0
      priority_developer_counts[priority_key][dev_name] += count
    end

    # Get developers same way as existing method - from tickets that have developers
    all_developers = completed_tickets.joins(:developer).pluck("developers.name").uniq.sort

    colors = [
      "rgba(52, 152, 219, 0.6)",   # Blue
      "rgba(46, 204, 113, 0.6)",   # Green
      "rgba(241, 196, 15, 0.6)",   # Yellow
      "rgba(231, 76, 60, 0.6)",    # Red
      "rgba(155, 89, 182, 0.6)",   # Purple
      "rgba(230, 126, 34, 0.6)",   # Orange
      "rgba(26, 188, 156, 0.6)",   # Turquoise
      "rgba(149, 165, 166, 0.6)"   # Gray
    ]

    all_developers.each_with_index do |dev, index|
      developer_colors[dev] = {
        background: colors[index % colors.length],
        border: colors[index % colors.length].gsub("0.6", "1")
      }
    end

    # Build datasets - one dataset per developer (only those with completed tickets)
    datasets = []
    all_developers.each do |developer|
      data = []
      priority_developer_counts.keys.sort.each do |priority|
        count = priority_developer_counts[priority][developer] || 0
        data << count
      end

      # Only include developers who have completed tickets (same as existing logic)
      if data.sum > 0
        datasets << {
          label: developer.length > 12 ? "#{developer[0...9]}..." : developer,
          data: data,
          backgroundColor: developer_colors[developer][:background],
          borderColor: developer_colors[developer][:border],
          borderWidth: 1
        }
      end
    end

    {
      labels: priority_developer_counts.keys.sort,
      datasets: datasets
    }
  end

  def get_repository_stats(since)
    scoped_repositories.joins(:commits)
                      .where("commits.committed_at >= ?", since)
                      .group("repositories.id", "repositories.name")
                      .order("COUNT(commits.id) DESC")
                      .limit(10)
                      .pluck("repositories.name", "COUNT(commits.id)")
                      .map { |name, count| { name: name, commits: count } }
  end

  def get_developer_stats(since)
    scoped_developers.joins(:commits)
                    .where("commits.committed_at >= ?", since)
                    .group("developers.id", "developers.name")
                    .order("COUNT(commits.id) DESC")
                    .limit(10)
                    .pluck("developers.name", "COUNT(commits.id)")
                    .map { |name, count| { name: name, commits: count } }
  end

  def group_activity_by_hours(commits, tickets, since)
    labels = (0..23).map { |hour| "#{hour}h ago" }.reverse

    commit_data = Array.new(24, 0)
    ticket_data = Array.new(24, 0)

    commits.each do |commit|
      hour_diff = ((Time.current - commit.committed_at) / 1.hour).to_i
      commit_data[23 - hour_diff] += 1 if hour_diff >= 0 && hour_diff < 24
    end

    tickets.each do |ticket|
      hour_diff = ((Time.current - ticket.updated_at_jira) / 1.hour).to_i
      ticket_data[23 - hour_diff] += 1 if hour_diff >= 0 && hour_diff < 24
    end

    { labels: labels, commit_data: commit_data, ticket_data: ticket_data }
  end

  def group_activity_by_days(commits, tickets, since)
    labels = (6.downto(0)).map { |days_ago| (Date.current - days_ago.days).strftime("%a") }

    commit_data = Array.new(7, 0)
    ticket_data = Array.new(7, 0)

    commits.each do |commit|
      days_ago = (Date.current - commit.committed_at.to_date).to_i
      day_index = 6 - days_ago
      commit_data[day_index] += 1 if day_index >= 0 && day_index < 7
    end

    tickets.each do |ticket|
      days_ago = (Date.current - ticket.updated_at_jira.to_date).to_i
      day_index = 6 - days_ago
      ticket_data[day_index] += 1 if day_index >= 0 && day_index < 7
    end

    { labels: labels, commit_data: commit_data, ticket_data: ticket_data }
  end

  def group_activity_by_weeks(commits, tickets, since)
    labels = 4.times.map { |week| "Week #{week + 1}" }

    commit_data = Array.new(4, 0)
    ticket_data = Array.new(4, 0)

    commits.each do |commit|
      week_index = ((commit.committed_at - since) / 1.week).to_i
      commit_data[week_index] += 1 if week_index >= 0 && week_index < 4
    end

    tickets.each do |ticket|
      week_index = ((ticket.updated_at_jira - since) / 1.week).to_i
      ticket_data[week_index] += 1 if week_index >= 0 && week_index < 4
    end

    { labels: labels, commit_data: commit_data, ticket_data: ticket_data }
  end

  def group_activity_by_months(commits, tickets, since)
    labels = 6.times.map { |month| (since + month.months).strftime("%b") }

    commit_data = Array.new(6, 0)
    ticket_data = Array.new(6, 0)

    commits.each do |commit|
      month_diff = ((commit.committed_at.year - since.year) * 12 + commit.committed_at.month - since.month)
      commit_data[month_diff] += 1 if month_diff >= 0 && month_diff < 6
    end

    tickets.each do |ticket|
      month_diff = ((ticket.updated_at_jira.year - since.year) * 12 + ticket.updated_at_jira.month - since.month)
      ticket_data[month_diff] += 1 if month_diff >= 0 && month_diff < 6
    end

    { labels: labels, commit_data: commit_data, ticket_data: ticket_data }
  end

  def group_activity_by_quarters(commits, tickets, since)
    labels = [ "Q1", "Q2", "Q3", "Q4" ]

    commit_data = Array.new(4, 0)
    ticket_data = Array.new(4, 0)

    commits.each do |commit|
      quarter = ((commit.committed_at.month - 1) / 3).to_i
      commit_data[quarter] += 1 if quarter >= 0 && quarter < 4
    end

    tickets.each do |ticket|
      quarter = ((ticket.updated_at_jira.month - 1) / 3).to_i
      ticket_data[quarter] += 1 if quarter >= 0 && quarter < 4
    end

    { labels: labels, commit_data: commit_data, ticket_data: ticket_data }
  end

  # Existing methods remain unchanged
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

  # Add these methods to your BaseAnalytics concern

  def get_code_impact_by_developer_data(since)
    commits = scoped_commits.includes(:developer)
                            .where("committed_at >= ?", since)
                            .where.not(additions: 0, deletions: 0) # Only commits with stats

    if commits.empty?
      return {
        labels: [ "No Data" ],
        datasets: [
          { label: "Lines Added", data: [ 0 ], backgroundColor: "rgba(46, 204, 113, 0.6)" },
          { label: "Lines Deleted", data: [ 0 ], backgroundColor: "rgba(231, 76, 60, 0.6)" }
        ]
      }
    end

    # Group by developer and sum additions/deletions
    developer_stats = {}
    commits.each do |commit|
      next unless commit.developer

      dev_name = commit.developer.name
      developer_stats[dev_name] ||= { additions: 0, deletions: 0, commits: 0 }
      developer_stats[dev_name][:additions] += commit.additions
      developer_stats[dev_name][:deletions] += commit.deletions
      developer_stats[dev_name][:commits] += 1
    end

    # Sort by total impact (additions + deletions) descending
    sorted_developers = developer_stats.sort_by { |dev, stats| -(stats[:additions] + stats[:deletions]) }.to_h

    # Prepare chart data
    labels = sorted_developers.keys.map { |name| name.length > 12 ? "#{name[0...9]}..." : name }
    additions_data = sorted_developers.values.map { |stats| stats[:additions] }
    deletions_data = sorted_developers.values.map { |stats| stats[:deletions] }

    {
      labels: labels,
      datasets: [
        {
          label: "Lines Added",
          data: additions_data,
          backgroundColor: "rgba(46, 204, 113, 0.6)",
          borderColor: "rgba(46, 204, 113, 1)",
          borderWidth: 1
        },
        {
          label: "Lines Deleted",
          data: deletions_data,
          backgroundColor: "rgba(231, 76, 60, 0.6)",
          borderColor: "rgba(231, 76, 60, 1)",
          borderWidth: 1
        }
      ]
    }
  end

  def get_code_changes_by_developer_and_repo_data(since)
    commits = scoped_commits.includes(:developer, :repository)
                            .where("committed_at >= ?", since)
                            .where.not(additions: 0, deletions: 0) # Only commits with stats

    if commits.empty?
      return {
        labels: [ "No Data" ],
        datasets: [ {
          label: "Lines Changed",
          data: [ 0 ],
          backgroundColor: "rgba(52, 152, 219, 0.6)"
        } ]
      }
    end

    # Group by developer and repository
    developer_repo_stats = {}
    commits.each do |commit|
      next unless commit.developer && commit.repository

      dev_name = commit.developer.name
      repo_name = commit.repository.name

      developer_repo_stats[dev_name] ||= {}
      developer_repo_stats[dev_name][repo_name] ||= 0
      developer_repo_stats[dev_name][repo_name] += (commit.additions + commit.deletions)
    end

    # Get all unique repositories for consistent coloring
    all_repos = commits.map { |c| c.repository.name }.uniq.sort

    # Color palette for repositories
    colors = [
      "rgba(52, 152, 219, 0.6)",   # Blue
      "rgba(46, 204, 113, 0.6)",   # Green
      "rgba(241, 196, 15, 0.6)",   # Yellow
      "rgba(231, 76, 60, 0.6)",    # Red
      "rgba(155, 89, 182, 0.6)",   # Purple
      "rgba(230, 126, 34, 0.6)",   # Orange
      "rgba(26, 188, 156, 0.6)",   # Turquoise
      "rgba(149, 165, 166, 0.6)"   # Gray
    ]

    # Sort developers by total changes (descending)
    sorted_developers = developer_repo_stats.sort_by do |dev, repos|
      -repos.values.sum
    end.to_h

    # Prepare chart data
    labels = sorted_developers.keys.map { |name| name.length > 12 ? "#{name[0...9]}..." : name }

    # Create one dataset per repository
    datasets = []
    all_repos.each_with_index do |repo, index|
      repo_data = sorted_developers.keys.map do |dev|
        sorted_developers[dev][repo] || 0
      end

      # Only include repositories that have data
      if repo_data.sum > 0
        datasets << {
          label: repo.length > 20 ? "#{repo[0...17]}..." : repo,
          data: repo_data,
          backgroundColor: colors[index % colors.length],
          borderColor: colors[index % colors.length].gsub("0.6", "1"),
          borderWidth: 1
        }
      end
    end

    {
      labels: labels,
      datasets: datasets
    }
  end
end
