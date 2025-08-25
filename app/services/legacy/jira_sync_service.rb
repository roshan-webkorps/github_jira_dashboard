class Legacy::JiraSyncService < BaseJiraSyncService
  protected

  def get_jira_service
    Legacy::JiraService.new
  end

  def get_project_keys
    "PAN1"
  end

  def get_app_type
    "legacy"
  end

  def is_known_developer?(name, email, account_id)
    get_known_developer_account_ids.include?(account_id)
  end

  def get_known_developer_account_ids
    [
      "62bff472118b20bee2bdc815",  # Sheela Gouri
      "6148dba278b7a1006aa8748c",  # Shubham
      "712020:6299518f-0328-4207-8302-c81123698c07",  # vsingh
      "63216307f8c7bc1f35837f67",  # rohitmahajan
      "5f5f73becacd8300775466c4",  # Priya Thakur
      "5f46ee1b347294003e7435bd"   # mehul
    ]
  end
end
