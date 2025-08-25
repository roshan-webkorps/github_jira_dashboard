class BaseGithubSyncService
  def initialize
    @github = get_github_service
  end

  def sync_all_data(since = 1.year.ago)
    Rails.logger.info "Starting #{self.class.name} data sync since #{since}..."

    # Get repositories first
    repos_data = sync_repositories
    return { error: "Failed to fetch repositories" } if repos_data[:error]

    # Sync commits and PRs for each repo
    repos_data[:repositories].each do |repo|
      sync_repository_commits(repo, since)
      sync_repository_pull_requests(repo, since)
    end

    Rails.logger.info "#{self.class.name} data sync completed"
    {
      repositories: repos_data[:count],
      developers: Developer.where(app_type: get_app_type).count,
      commits: Commit.where(app_type: get_app_type).count,
      pull_requests: PullRequest.where(app_type: get_app_type).count
    }
  end

  def sync_repositories
    Rails.logger.info "Syncing repositories..."

    # Get the specific repositories we want to sync
    target_repos = get_target_repositories

    repos = @github.fetch_user_repos
    return { error: repos[:error] } if repos.is_a?(Hash) && repos[:error]

    # Filter to only the repositories we want
    filtered_repos = repos.select do |repo_data|
      target_repos.key?(repo_data["id"].to_s)
    end

    Rails.logger.info "Found #{repos.count} total repositories, filtering to #{filtered_repos.count} target repositories"
    count = 0
    repositories = []

    filtered_repos.each do |repo_data|
      repo = upsert_repository(repo_data)

      if repo.persisted?
        count += 1
        repositories << repo
        Rails.logger.info "Synced repository: #{repo.full_name}"
      else
        Rails.logger.error "Failed to sync repository: #{repo_data['full_name']}"
        Rails.logger.error "Errors: #{repo.errors.full_messages.join(', ')}"
      end
    end

    # Log any missing repositories
    synced_ids = filtered_repos.map { |r| r["id"].to_s }
    missing_repos = target_repos.reject { |id, name| synced_ids.include?(id) }
    if missing_repos.any?
      Rails.logger.warn "Missing repositories (not found in GitHub response):"
      missing_repos.each { |id, name| Rails.logger.warn "  - #{name} (#{id})" }
    end

    Rails.logger.info "Synced #{count} repositories total"
    { count: count, repositories: repositories }
  end

  def sync_repository_commits(repository, since = 1.year.ago)
    Rails.logger.info "Syncing commits for #{repository.full_name} since #{since}..."

    start_time = Time.current
    commits = @github.fetch_repo_commits(repository.owner, repository.name, since)
    api_time = Time.current - start_time

    return if commits.is_a?(Hash) && commits[:error]

    Rails.logger.info "API fetch took #{api_time.round(2)} seconds, got #{commits.count} commits"

    count = 0
    db_start = Time.current
    commits.each do |commit_data|
      next unless commit_data["author"] # Skip commits without author

      # Find or create developer
      author_data = commit_data["author"] || commit_data["commit"]["author"]
      developer = upsert_developer(author_data)
      next unless developer

      # Create or update commit
      commit = upsert_commit(commit_data, developer, repository)
      count += 1 if commit.persisted?
    end
    db_time = Time.current - db_start

    Rails.logger.info "Synced #{count} commits (DB operations: #{db_time.round(2)}s)"
  end

  def sync_repository_pull_requests(repository, since = 1.year.ago)
    Rails.logger.info "Syncing pull requests for #{repository.full_name} since #{since}..."

    start_time = Time.current
    prs = @github.fetch_repo_pull_requests(repository.owner, repository.name, "all", since)
    api_time = Time.current - start_time

    return if prs.is_a?(Hash) && prs[:error]

    Rails.logger.info "API fetch took #{api_time.round(2)} seconds, got #{prs.count} PRs"

    count = 0
    db_start = Time.current
    prs.each do |pr_data|
      next unless pr_data["user"] # Skip PRs without user

      # Find or create developer
      developer = upsert_developer(pr_data["user"])
      next unless developer

      # Create or update pull request
      pr = upsert_pull_request(pr_data, developer, repository)
      count += 1 if pr.persisted?
    end
    db_time = Time.current - db_start

    Rails.logger.info "Synced #{count} pull requests (DB operations: #{db_time.round(2)}s)"
  end

  protected

  # Abstract methods to be implemented by subclasses
  def get_github_service
    raise NotImplementedError, "Subclasses must implement get_github_service"
  end

  def get_target_repositories
    raise NotImplementedError, "Subclasses must implement get_target_repositories"
  end

  def get_app_type
    raise NotImplementedError, "Subclasses must implement get_app_type"
  end

  private

  def upsert_repository(repo_data)
    repo = Repository.find_or_initialize_by(
      github_id: repo_data["id"].to_s,
      app_type: get_app_type
    )

    repo.assign_attributes(
      name: repo_data["name"],
      full_name: repo_data["full_name"],
      owner: repo_data["owner"]["login"],
      description: repo_data["description"],
      language: repo_data["language"],
      private: repo_data["private"]
    )

    repo.save
    repo
  end

  def upsert_developer(user_data)
    return nil unless user_data

    username = user_data["login"]
    email = user_data["email"] || "#{username}@github.local"
    name = user_data["name"] || username

    developer = Developer.find_or_initialize_by(
      github_username: username,
      app_type: get_app_type
    )

    developer.assign_attributes(
      name: name,
      email: email,
      avatar_url: user_data["avatar_url"]
    )

    if developer.save
      developer
    else
      Rails.logger.error "Failed to save developer: #{developer.errors.full_messages.join(', ')}"
      Rails.logger.error "Developer data: #{user_data.inspect}"
      nil
    end
  end

  def upsert_commit(commit_data, developer, repository)
    commit = Commit.find_or_initialize_by(
      sha: commit_data["sha"],
      app_type: get_app_type
    )

    commit.assign_attributes(
      message: commit_data["commit"]["message"],
      developer: developer,
      repository: repository,
      committed_at: Time.parse(commit_data["commit"]["author"]["date"]),
      additions: 0, # We'll enhance this later if needed
      deletions: 0
    )

    commit.save
    commit
  end

  def upsert_pull_request(pr_data, developer, repository)
    pr = PullRequest.find_or_initialize_by(
      github_id: pr_data["id"].to_s,
      app_type: get_app_type
    )

    pr.assign_attributes(
      number: pr_data["number"],
      title: pr_data["title"],
      body: pr_data["body"],
      state: pr_data["state"],
      developer: developer,
      repository: repository,
      opened_at: Time.parse(pr_data["created_at"]),
      closed_at: pr_data["closed_at"] ? Time.parse(pr_data["closed_at"]) : nil,
      merged_at: pr_data["merged_at"] ? Time.parse(pr_data["merged_at"]) : nil
    )

    pr.save
    pr
  end
end
