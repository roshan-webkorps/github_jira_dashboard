namespace :github do
  desc "Initial sync of GitHub data for the last year"
  task initial_sync: :environment do
    puts "Starting initial GitHub data sync..."
    
    unless ENV['GITHUB_TOKEN']
      puts "ERROR: GITHUB_TOKEN environment variable is required"
      exit 1
    end

    sync_service = GithubSyncService.new
    result = sync_service.sync_all_data(1.year.ago)

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully!"
      puts "Repositories: #{result[:repositories]}"
      puts "Developers: #{result[:developers]}"
      puts "Commits: #{result[:commits]}"
      puts "Pull Requests: #{result[:pull_requests]}"
    end
  end

  desc "Incremental sync of GitHub data from the last day"
  task incremental_sync: :environment do
    puts "Starting incremental GitHub data sync..."
    
    unless ENV['GITHUB_TOKEN']
      puts "ERROR: GITHUB_TOKEN environment variable is required"
      exit 1
    end

    sync_service = GithubSyncService.new
    result = sync_service.sync_all_data(1.day.ago)

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully!"
      puts "Repositories: #{result[:repositories]}"
      puts "Developers: #{result[:developers]}"
      puts "Commits: #{result[:commits]}"
      puts "Pull Requests: #{result[:pull_requests]}"
    end
  end
end
