class BaseJiraService
  include HTTParty

  def initialize(base_uri, username, api_token)
    @base_uri = base_uri
    @options = {
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      },
      basic_auth: {
        username: username,
        password: api_token
      }
    }

    self.class.base_uri @base_uri
  end

  def fetch_projects
    response = self.class.get("/rest/api/3/project", @options)
    handle_response(response)
  end

  def fetch_issues_paginated(project_key = nil, since = nil, start_at = 0, max_results = 100)
    jql = build_jql_query(project_key, since)

    response = self.class.get("/rest/api/3/search/jql", @options.merge(
      query: {
        jql: jql,
        startAt: start_at,
        maxResults: max_results,
        fields: "key,summary,description,status,priority,issuetype,assignee,creator,created,updated",
        expand: "changelog"
      }
    ))

    handle_response(response)
  end

  def fetch_issues(project_key = nil, since = nil)
    # Keep the old method for backward compatibility, but use pagination
    fetch_issues_paginated(project_key, since, 0, 100)
  end

  def fetch_issue_by_key(issue_key)
    response = self.class.get("/rest/api/3/issue/#{issue_key}", @options.merge(
      query: {
        fields: "key,summary,description,status,priority,issuetype,assignee,creator,created,updated",
        expand: "changelog"
      }
    ))

    handle_response(response)
  end

  def test_connection
    response = self.class.get("/rest/api/3/myself", @options)
    handle_response(response)
  end

  protected

  def build_jql_query(project_key, since)
    # This will be overridden by subclasses to handle different project keys
    conditions = []

    # Default project filter - should be overridden
    project = project_key || get_default_project_key
    if project.is_a?(Array)
      project_list = project.map { |p| "\"#{p}\"" }.join(", ")
      conditions << "project IN (#{project_list})"
    else
      conditions << "project = #{project}"
    end

    # Exclude subtasks
    conditions << "issuetype != Subtask"

    if since
      formatted_date = since.strftime("%Y-%m-%d")

      # If since is more than 1 day ago, use created date
      # If since is 1 day or less, use updated date
      if since <= 1.day.ago
        conditions << "updated >= '#{formatted_date}'"
      else
        conditions << "created >= '#{formatted_date}'"
      end
    end

    conditions.join(" AND ") + " ORDER BY created DESC"
  end

  def get_default_project_key
    # Override in subclasses
    raise NotImplementedError, "Subclasses must implement get_default_project_key"
  end

  def handle_response(response)
    case response.code
    when 200
      response.parsed_response
    when 400
      Rails.logger.error "Jira API: Bad Request - #{response.parsed_response}"
      { error: "Bad request - check your query" }
    when 401
      Rails.logger.error "Jira API: Unauthorized - check credentials"
      { error: "Unauthorized - check Jira credentials" }
    when 403
      Rails.logger.error "Jira API: Forbidden - insufficient permissions"
      { error: "Forbidden - insufficient permissions" }
    when 404
      Rails.logger.error "Jira API: Resource not found"
      { error: "Resource not found" }
    else
      Rails.logger.error "Jira API: Error #{response.code} - #{response.message}"
      { error: "Jira API error: #{response.code}" }
    end
  end
end
