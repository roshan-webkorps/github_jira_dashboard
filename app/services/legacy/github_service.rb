class Legacy::GithubService < BaseGithubService
  def initialize
    super(ENV["GITHUB_TOKEN"])
  end
end
