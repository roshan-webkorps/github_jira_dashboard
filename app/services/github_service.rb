class GithubService
  include HTTParty
  base_uri "https://api.github.com"

  def initialize
    @options = {
      headers: {
        "Authorization" => "token #{ENV['GITHUB_TOKEN']}",
        "Accept" => "application/vnd.github.v3+json",
        "User-Agent" => "GitHub-Jira-Dashboard"
      }
    }
  end

  def fetch_user_repos(username = nil)
    endpoint = username ? "/users/#{username}/repos" : "/user/repos"

    all_repos = []
    page = 1
    per_page = 100

    loop do
      response = self.class.get(endpoint, @options.merge(
        query: {
          type: "all",
          sort: "updated",
          per_page: per_page,
          page: page
        }
      ))

      result = handle_response(response)
      return result if result.is_a?(Hash) && result[:error]

      break if result.empty?

      all_repos.concat(result)
      page += 1
    end

    all_repos
  end

  def fetch_repo_commits(owner, repo, since = nil)
    endpoint = "/repos/#{owner}/#{repo}/commits"

    all_commits = []
    page = 1
    per_page = 100

    loop do
      query = { per_page: per_page, page: page }
      query[:since] = since.iso8601 if since

      response = self.class.get(endpoint, @options.merge(query: query))
      result = handle_response(response)
      return result if result.is_a?(Hash) && result[:error]

      break if result.empty?

      all_commits.concat(result)
      page += 1
    end

    all_commits
  end

  def fetch_repo_pull_requests(owner, repo, state = "all", since = nil)
    endpoint = "/repos/#{owner}/#{repo}/pulls"

    all_prs = []
    page = 1
    per_page = 100

    loop do
      query = {
        state: state,
        sort: "created",
        direction: "desc",
        per_page: per_page,
        page: page
      }

      response = self.class.get(endpoint, @options.merge(query: query))
      result = handle_response(response)
      return result if result.is_a?(Hash) && result[:error]

      break if result.empty?

      if since
        filtered_result = result.select { |pr| Time.parse(pr["created_at"]) >= since }
        all_prs.concat(filtered_result)

        break if result.any? { |pr| Time.parse(pr["created_at"]) < since }
      else
        all_prs.concat(result)
      end

      page += 1
    end

    all_prs
  end

  def fetch_authenticated_user
    response = self.class.get("/user", @options)
    handle_response(response)
  end

  private

  def handle_response(response)
    case response.code
    when 200
      response.parsed_response
    when 401
      Rails.logger.error "GitHub API: Unauthorized - check your token"
      { error: "Unauthorized - check your GitHub token" }
    when 403
      Rails.logger.error "GitHub API: Rate limit exceeded"
      { error: "Rate limit exceeded" }
    when 404
      Rails.logger.error "GitHub API: Resource not found"
      { error: "Resource not found" }
    else
      Rails.logger.error "GitHub API: Error #{response.code} - #{response.message}"
      { error: "GitHub API error: #{response.code}" }
    end
  end
end
