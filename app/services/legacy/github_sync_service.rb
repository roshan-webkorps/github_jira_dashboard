class Legacy::GithubSyncService < BaseGithubSyncService
  protected

  def get_github_service
    Legacy::GithubService.new
  end

  def get_target_repositories
    {
      "339825464" => "ap-kubernetes-helm",
      "120736547" => "asset_panda_web_app",
      "211844555" => "ap_audit_api",
      "269534419" => "ap-reservation-api",
      "196480441" => "ap-barcode-api",
      "511952365" => "help-desk",
      "288275646" => "ap_jobs_service",
      "173906727" => "asset_panda_zendesk_integration",
      "463112505" => "assetpanda-jira-app",
      "225449659" => "panda3"
    }
  end

  def get_app_type
    "legacy"
  end
end
