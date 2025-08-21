class GithubSyncService
  def initialize
    @github = GithubService.new
  end

  def sync_all_data
    Rails.logger.info "Starting GitHub data sync..."
    
    # Get repositories first
    repos_data = sync_repositories
    return { error: "Failed to fetch repositories" } if repos_data[:error]

    # Sync commits and PRs for each repo
    repos_data[:repositories].each do |repo|
      sync_repository_commits(repo)
      sync_repository_pull_requests(repo)
    end

    Rails.logger.info "GitHub data sync completed"
    {
      repositories: repos_data[:count],
      developers: Developer.count,
      commits: Commit.count,
      pull_requests: PullRequest.count
    }
  end

  def sync_repositories
    Rails.logger.info "Syncing repositories..."
    
    repos = @github.fetch_user_repos
    return { error: repos[:error] } if repos.is_a?(Hash) && repos[:error]

    count = 0
    repositories = []

    repos.each do |repo_data|
      repo = Repository.find_or_create_by(github_id: repo_data['id'].to_s) do |r|
        r.name = repo_data['name']
        r.full_name = repo_data['full_name']
        r.owner = repo_data['owner']['login']
        r.description = repo_data['description']
        r.language = repo_data['language']
        r.private = repo_data['private']
      end

      if repo.persisted?
        count += 1
        repositories << repo
        Rails.logger.info "  ✓ Synced repository: #{repo.full_name}"
      else
        Rails.logger.error "  ✗ Failed to sync repository: #{repo_data['full_name']}"
      end
    end

    { count: count, repositories: repositories }
  end

  def sync_repository_commits(repository, since = 1.month.ago)
    Rails.logger.info "  Syncing commits for #{repository.full_name}..."
    
    commits = @github.fetch_repo_commits(repository.owner, repository.name, since)
    return if commits.is_a?(Hash) && commits[:error]

    count = 0
    commits.each do |commit_data|
      next unless commit_data['author'] # Skip commits without author

      # Find or create developer
      author_data = commit_data['author'] || commit_data['commit']['author']
      developer = find_or_create_developer(author_data)
      next unless developer

      # Create commit
      commit = Commit.find_or_create_by(sha: commit_data['sha']) do |c|
        c.message = commit_data['commit']['message']
        c.developer = developer
        c.repository = repository
        c.committed_at = Time.parse(commit_data['commit']['author']['date'])
        c.additions = 0 # We'll enhance this later if needed
        c.deletions = 0
      end

      count += 1 if commit.persisted?
    end

    Rails.logger.info "    ✓ Synced #{count} commits"
  end

  def sync_repository_pull_requests(repository, since = 1.month.ago)
    Rails.logger.info "  Syncing pull requests for #{repository.full_name}..."
    
    prs = @github.fetch_repo_pull_requests(repository.owner, repository.name, 'all', since)
    return if prs.is_a?(Hash) && prs[:error]

    count = 0
    prs.each do |pr_data|
      next unless pr_data['user'] # Skip PRs without user

      # Find or create developer
      developer = find_or_create_developer(pr_data['user'])
      next unless developer

      # Create pull request
      pr = PullRequest.find_or_create_by(github_id: pr_data['id'].to_s) do |p|
        p.number = pr_data['number']
        p.title = pr_data['title']
        p.body = pr_data['body']
        p.state = pr_data['state']
        p.developer = developer
        p.repository = repository
        p.opened_at = Time.parse(pr_data['created_at'])
        p.closed_at = pr_data['closed_at'] ? Time.parse(pr_data['closed_at']) : nil
        p.merged_at = pr_data['merged_at'] ? Time.parse(pr_data['merged_at']) : nil
      end

      count += 1 if pr.persisted?
    end

    Rails.logger.info "    ✓ Synced #{count} pull requests"
  end

  private

  def find_or_create_developer(user_data)
    return nil unless user_data

    username = user_data['login']
    email = user_data['email'] || "#{username}@github.local"
    name = user_data['name'] || username

    Developer.find_or_create_by(github_username: username) do |dev|
      dev.name = name
      dev.email = email
      dev.avatar_url = user_data['avatar_url']
    end
  end
end
