class Pioneer::GithubService < BaseGithubService
  def initialize
    super(ENV["PIONEER_GITHUB_TOKEN"])
  end
end
