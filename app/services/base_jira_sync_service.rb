class BaseJiraSyncService
  def initialize
    @jira = get_jira_service
  end

  def sync_all_data(since = 1.year.ago)
    Rails.logger.info "Starting #{self.class.name} data sync since #{since}..."

    project_keys = get_project_keys
    total_synced = 0

    if project_keys.is_a?(Array)
      # Multiple projects
      project_keys.each do |project_key|
        result = sync_issues(project_key, since)

        if result[:error]
          Rails.logger.error "Jira sync failed for project #{project_key}: #{result[:error]}"
          return result
        end

        total_synced += result[:synced_count]
      end
    else
      # Single project
      result = sync_issues(project_keys, since)

      if result[:error]
        Rails.logger.error "Jira sync failed: #{result[:error]}"
        return result
      end

      total_synced = result[:synced_count]
    end

    Rails.logger.info "#{self.class.name} data sync completed"
    {
      tickets: Ticket.where(app_type: get_app_type).count,
      synced_count: total_synced
    }
  end

  def sync_issues(project_key, since = 1.year.ago)
    Rails.logger.info "Syncing Jira issues from project #{project_key}#{since ? " since #{since.strftime('%Y-%m-%d')}" : " (all time)"}..."

    synced_count = 0
    start_at = 0
    max_results = 100

    loop do
      Rails.logger.info "  Fetching issues #{start_at + 1} to #{start_at + max_results}..."

      response = @jira.fetch_issues_paginated(project_key, since, start_at, max_results)
      return { error: response[:error] } if response.is_a?(Hash) && response[:error]

      issues = response["issues"] || []
      total = response["total"] || 0

      Rails.logger.info "  Found #{issues.count} issues (#{synced_count + issues.count} of #{total} total)"

      # Process this batch of issues
      issues.each do |issue_data|
        ticket = upsert_single_issue(issue_data)
        synced_count += 1 if ticket
      end

      # Check if we've got all the issues
      break if issues.count < max_results || (start_at + issues.count) >= total

      start_at += max_results
    end

    Rails.logger.info "Synced #{synced_count} Jira issues from project #{project_key}"
    { synced_count: synced_count }
  end

  protected

  # Abstract methods to be implemented by subclasses
  def get_jira_service
    raise NotImplementedError, "Subclasses must implement get_jira_service"
  end

  def get_project_keys
    raise NotImplementedError, "Subclasses must implement get_project_keys"
  end

  def get_app_type
    raise NotImplementedError, "Subclasses must implement get_app_type"
  end

  def is_known_developer?(name, email, account_id)
    raise NotImplementedError, "Subclasses must implement is_known_developer?"
  end

  def get_known_developer_account_ids
    raise NotImplementedError, "Subclasses must implement get_known_developer_account_ids"
  end

  private

  def upsert_single_issue(issue_data)
    # Find the developer who actually worked on this ticket
    developer = find_developer_from_history(issue_data)

    # Create or update ticket
    ticket = Ticket.find_or_initialize_by(jira_id: issue_data["id"])

    ticket.assign_attributes(
      key: issue_data["key"],
      title: issue_data.dig("fields", "summary") || "No title",
      status: issue_data.dig("fields", "status", "name") || "Unknown",
      priority: issue_data.dig("fields", "priority", "name"),
      ticket_type: issue_data.dig("fields", "issuetype", "name"),
      developer: developer,
      project_key: extract_project_key(issue_data["key"]),
      created_at_jira: parse_jira_date(issue_data.dig("fields", "created")),
      updated_at_jira: parse_jira_date(issue_data.dig("fields", "updated")),
      app_type: get_app_type
    )

    if ticket.save
      Rails.logger.info "Synced ticket: #{ticket.key} -> #{developer&.name || 'No developer'}"
      ticket
    else
      Rails.logger.error "Failed to sync ticket: #{issue_data['key']}"
      Rails.logger.error "Errors: #{ticket.errors.full_messages.join(', ')}"
      nil
    end
  end

  def find_developer_from_history(issue_data)
    # First, try to find developer from assignment history
    developer = find_developer_from_assignment_history(issue_data)
    return developer if developer

    # Fallback: try current assignee if it looks like a developer
    current_assignee = issue_data.dig("fields", "assignee")
    if current_assignee && looks_like_developer?(current_assignee)
      return upsert_developer_from_jira(current_assignee)
    end

    # Last resort: try the creator if it looks like a developer
    creator = issue_data.dig("fields", "creator")
    if creator && looks_like_developer?(creator)
      return upsert_developer_from_jira(creator)
    end

    nil # No developer found
  end

  def find_developer_from_assignment_history(issue_data)
    changelog = issue_data.dig("changelog", "histories")
    return nil unless changelog

    # Look through the assignment history for developers
    developer_assignments = []

    changelog.each do |history|
      history["items"]&.each do |item|
        if item["field"] == "assignee" && item["to"]
          # Someone was assigned - check if they're a developer by account_id
          assignee_id = item["to"]
          assignee_name = item["toString"]

          # Only check account_id, not name
          if is_known_developer?(nil, nil, assignee_id)
            developer_assignments << {
              assignee_id: assignee_id,
              assignee_name: assignee_name,
              assigned_at: parse_jira_date(history["created"])
            }
          end
        end
      end
    end

    # Return the most recent developer assignment
    if developer_assignments.any?
      recent_assignment = developer_assignments.last
      # Create a mock user object to pass to upsert_developer_from_jira
      mock_user = {
        "accountId" => recent_assignment[:assignee_id],
        "displayName" => recent_assignment[:assignee_name],
        "emailAddress" => nil
      }
      return upsert_developer_from_jira(mock_user)
    end

    nil
  end

  def looks_like_developer?(user_data)
    return false unless user_data
    account_id = user_data["accountId"]
    # Only check account_id
    is_known_developer?(nil, nil, account_id)
  end

  def upsert_developer_from_jira(assignee_data)
    return nil unless assignee_data

    account_id = assignee_data["accountId"]

    # First check if this person is actually a developer (by account_id only)
    unless is_known_developer?(nil, nil, account_id)
      return nil
    end

    # Find by jira_username (which is the account_id) and type
    developer = Developer.find_or_initialize_by(
      jira_username: account_id,
      app_type: get_app_type
    )

    # Update attributes
    display_name = assignee_data["displayName"]
    email = assignee_data["emailAddress"] || "#{account_id}@jira.local"

    developer.assign_attributes(
      name: display_name || account_id,
      email: email
    )

    developer.save
    developer
  end

  def extract_project_key(issue_key)
    # Extract project key from issue key (e.g., "PROJ-123" -> "PROJ")
    issue_key.split("-").first
  end

  def parse_jira_date(date_string)
    return nil unless date_string
    Time.parse(date_string)
  rescue
    nil
  end
end
