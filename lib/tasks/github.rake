namespace :github do
  desc "Sync all GitHub data (repositories, commits, pull requests)"
  task sync: :environment do
    puts "Starting GitHub data sync..."
    
    unless ENV['GITHUB_TOKEN']
      puts "ERROR: GITHUB_TOKEN environment variable is required"
      exit 1
    end

    sync_service = GithubSyncService.new
    result = sync_service.sync_all_data

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully!"
      puts "Summary:"
      puts "  - Repositories: #{result[:repositories]}"
      puts "  - Developers: #{result[:developers]}"
      puts "  - Commits: #{result[:commits]}"
      puts "  - Pull Requests: #{result[:pull_requests]}"
    end
  end
end
