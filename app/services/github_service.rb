class GithubService
  include HTTParty
  base_uri 'https://api.github.com'

  def initialize
    @options = {
      headers: {
        'Authorization' => "token #{ENV['GITHUB_TOKEN']}",
        'Accept' => 'application/vnd.github.v3+json',
        'User-Agent' => 'GitHub-Jira-Dashboard'
      }
    }
  end

  def fetch_user_repos(username = nil)
    # If no username provided, fetch authenticated user's repos
    endpoint = username ? "/users/#{username}/repos" : "/user/repos"
    
    response = self.class.get(endpoint, @options.merge(
      query: { 
        type: 'all',
        sort: 'updated',
        per_page: 100
      }
    ))
    
    handle_response(response)
  end

  def fetch_repo_commits(owner, repo, since = nil)
    endpoint = "/repos/#{owner}/#{repo}/commits"
    query = { per_page: 100 }
    query[:since] = since.iso8601 if since
    
    response = self.class.get(endpoint, @options.merge(query: query))
    handle_response(response)
  end

  def fetch_repo_pull_requests(owner, repo, state = 'all', since = nil)
    endpoint = "/repos/#{owner}/#{repo}/pulls"
    query = { 
      state: state,
      sort: 'updated',
      direction: 'desc',
      per_page: 100
    }
    
    response = self.class.get(endpoint, @options.merge(query: query))
    
    # Filter by date if since is provided
    pulls = handle_response(response)
    if since && pulls.is_a?(Array)
      pulls.select { |pr| Time.parse(pr['created_at']) >= since }
    else
      pulls
    end
  end

  def fetch_authenticated_user
    response = self.class.get('/user', @options)
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
