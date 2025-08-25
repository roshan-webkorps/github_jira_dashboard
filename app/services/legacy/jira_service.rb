class Legacy::JiraService < BaseJiraService
  def initialize
    super(
      ENV["JIRA_URL"],
      ENV["JIRA_USERNAME"],
      ENV["JIRA_API_TOKEN"]
    )
  end

  protected

  def get_default_project_key
    "PAN1"
  end
end
