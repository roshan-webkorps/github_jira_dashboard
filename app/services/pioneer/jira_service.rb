class Pioneer::JiraService < BaseJiraService
  def initialize
    super(
      ENV["PIONEER_JIRA_URL"],
      ENV["PIONEER_JIRA_USERNAME"],
      ENV["PIONEER_JIRA_API_TOKEN"]
    )
  end

  protected

  def get_default_project_key
    [ "AP2", "ESI2", "PP", "INT2", "MOB2" ]
  end
end
