class Pioneer::GithubSyncService < BaseGithubSyncService
  protected

  def get_github_service
    Pioneer::GithubService.new
  end

  def get_target_repositories
    {
      "682341128" => "pioneer"
    }
  end

  def get_app_type
    "pioneer"
  end
end
