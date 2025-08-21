# app/services/jira_sync_service.rb
class JiraSyncService
  def initialize
    @jira = JiraService.new
  end

  def sync_all_data
    Rails.logger.info "Starting Jira data sync..."
    
    since = 1.year.ago
    result = sync_issues('PAN1', since)
    
    if result[:error]
      Rails.logger.error "Jira sync failed: #{result[:error]}"
      return result
    end

    Rails.logger.info "Jira data sync completed"
    {
      tickets: Ticket.count,
      synced_count: result[:synced_count]
    }
  end

  def sync_issues(project_key = 'PAN1', since = 1.year.ago)
    Rails.logger.info "Syncing Jira issues from project #{project_key}#{since ? " since #{since.strftime('%Y-%m-%d')}" : " (all time)"}..."
    
    synced_count = 0
    start_at = 0
    max_results = 100
    
    loop do
      Rails.logger.info "  Fetching issues #{start_at + 1} to #{start_at + max_results}..."
      
      response = @jira.fetch_issues_paginated(project_key, since, start_at, max_results)
      return { error: response[:error] } if response.is_a?(Hash) && response[:error]

      issues = response['issues'] || []
      total = response['total'] || 0
      
      Rails.logger.info "  Found #{issues.count} issues (#{synced_count + issues.count} of #{total} total)"
      
      # Process this batch of issues
      issues.each do |issue_data|
        ticket = sync_single_issue(issue_data)
        synced_count += 1 if ticket
      end
      
      # Check if we've got all the issues
      break if issues.count < max_results || (start_at + issues.count) >= total
      
      start_at += max_results
    end

    Rails.logger.info "Synced #{synced_count} Jira issues from project #{project_key}"
    { synced_count: synced_count }
  end

  private

  def sync_single_issue(issue_data)
    # Find the developer who actually worked on this ticket
    developer = find_developer_from_history(issue_data)
    
    # Create or update ticket
    ticket = Ticket.find_or_create_by(jira_id: issue_data['id']) do |t|
      t.key = issue_data['key']
      t.title = issue_data.dig('fields', 'summary') || 'No title'
      t.status = issue_data.dig('fields', 'status', 'name') || 'Unknown'
      t.priority = issue_data.dig('fields', 'priority', 'name')
      t.ticket_type = issue_data.dig('fields', 'issuetype', 'name')
      t.developer = developer
      t.project_key = extract_project_key(issue_data['key'])
      t.created_at_jira = parse_jira_date(issue_data.dig('fields', 'created'))
      t.updated_at_jira = parse_jira_date(issue_data.dig('fields', 'updated'))
    end

    if ticket.persisted?
      Rails.logger.info "  ✓ Synced ticket: #{ticket.key} -> #{developer&.name || 'No developer'}"
      ticket
    else
      Rails.logger.error "  ✗ Failed to sync ticket: #{issue_data['key']}"
      nil
    end
  end

  def find_developer_from_history(issue_data)
    # First, try to find developer from assignment history
    developer = find_developer_from_assignment_history(issue_data)
    return developer if developer

    # Fallback: try current assignee if it looks like a developer
    current_assignee = issue_data.dig('fields', 'assignee')
    if current_assignee && looks_like_developer?(current_assignee)
      return find_or_create_developer_from_jira(current_assignee)
    end

    # Last resort: try the creator if it looks like a developer
    creator = issue_data.dig('fields', 'creator')
    if creator && looks_like_developer?(creator)
      return find_or_create_developer_from_jira(creator)
    end

    nil # No developer found
  end

  def find_developer_from_assignment_history(issue_data)
    changelog = issue_data.dig('changelog', 'histories')
    return nil unless changelog

    # Look through the assignment history for developers
    developer_assignments = []

    changelog.each do |history|
      history['items']&.each do |item|
        if item['field'] == 'assignee' && item['to']
          # Someone was assigned - check if they're a developer by account_id
          assignee_id = item['to']
          assignee_name = item['toString']
          
          # Only check account_id, not name
          if is_known_developer?(nil, nil, assignee_id)
            developer_assignments << {
              assignee_id: assignee_id,
              assignee_name: assignee_name,
              assigned_at: parse_jira_date(history['created'])
            }
          end
        end
      end
    end

    # Return the most recent developer assignment
    if developer_assignments.any?
      recent_assignment = developer_assignments.last
      # Create a mock user object to pass to find_or_create_developer_from_jira
      mock_user = {
        'accountId' => recent_assignment[:assignee_id],
        'displayName' => recent_assignment[:assignee_name],
        'emailAddress' => nil
      }
      return find_or_create_developer_from_jira(mock_user)
    end

    nil
  end

  def looks_like_developer?(user_data)
    return false unless user_data
    account_id = user_data['accountId']
    # Only check account_id
    is_known_developer?(nil, nil, account_id)
  end

  def looks_like_developer_by_name?(name)
    # Not used anymore since we only check account_id
    false
  end

  def is_known_developer?(name, email, account_id)
    # Define your exact developers using their jira_username values
    known_developer_jira_usernames = [
      '62bff472118b20bee2bdc815',  # Sheela Gouri
      '6148dba278b7a1006aa8748c',  # Shubham
      '712020:6299518f-0328-4207-8302-c81123698c07',  # vsingh
      '63216307f8c7bc1f35837f67',  # rohitmahajan
      '5f5f73becacd8300775466c4',  # Priya Thakur
      '5f46ee1b347294003e7435bd'   # mehul
    ]
    
    # Simply check if account_id is in our known developers list
    known_developer_jira_usernames.include?(account_id)
  end

  def find_or_create_developer_from_jira(assignee_data)
    return nil unless assignee_data

    account_id = assignee_data['accountId']
    
    # First check if this person is actually a developer (by account_id only)
    unless is_known_developer?(nil, nil, account_id)
      return nil
    end

    # Find by jira_username (which is the account_id)
    developer = Developer.find_by(jira_username: account_id)

    # Create if not found
    unless developer
      display_name = assignee_data['displayName']
      email = assignee_data['emailAddress'] || "#{account_id}@jira.local"
      
      developer = Developer.create(
        name: display_name || account_id,
        email: email,
        jira_username: account_id
      )
    end

    developer
  end

  def extract_project_key(issue_key)
    # Extract project key from issue key (e.g., "PROJ-123" -> "PROJ")
    issue_key.split('-').first
  end

  def parse_jira_date(date_string)
    return nil unless date_string
    Time.parse(date_string)
  rescue
    nil
  end
end
