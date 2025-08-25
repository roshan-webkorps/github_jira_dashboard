namespace :github do
  namespace :legacy do
    desc "Initial sync of Legacy GitHub data for the last year"
    task initial_sync: :environment do
      puts "Starting initial Legacy GitHub data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["GITHUB_TOKEN"]
        puts "ERROR: GITHUB_TOKEN environment variable is required"
        exit 1
      end

      sync_service = Legacy::GithubSyncService.new
      result = sync_service.sync_all_data(1.year.ago)

      if result[:error]
        puts "Legacy GitHub sync failed: #{result[:error]}"
        exit 1
      else
        puts "Legacy GitHub sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Repositories: #{result[:repositories]}"
        puts "Developers: #{result[:developers]}"
        puts "Commits: #{result[:commits]}"
        puts "Pull Requests: #{result[:pull_requests]}"
      end
    end

    desc "Incremental sync of Legacy GitHub data from the last day"
    task incremental_sync: :environment do
      puts "Starting incremental Legacy GitHub data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["GITHUB_TOKEN"]
        puts "ERROR: GITHUB_TOKEN environment variable is required"
        exit 1
      end

      sync_service = Legacy::GithubSyncService.new
      result = sync_service.sync_all_data(1.day.ago)

      if result[:error]
        puts "Legacy GitHub sync failed: #{result[:error]}"
        exit 1
      else
        puts "Legacy GitHub sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Repositories: #{result[:repositories]}"
        puts "Developers: #{result[:developers]}"
        puts "Commits: #{result[:commits]}"
        puts "Pull Requests: #{result[:pull_requests]}"
      end
    end
  end

  namespace :pioneer do
    desc "Initial sync of Pioneer GitHub data for the last year"
    task initial_sync: :environment do
      puts "Starting initial Pioneer GitHub data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["PIONEER_GITHUB_TOKEN"]
        puts "ERROR: PIONEER_GITHUB_TOKEN environment variable is required"
        exit 1
      end

      sync_service = Pioneer::GithubSyncService.new
      result = sync_service.sync_all_data(1.year.ago)

      if result[:error]
        puts "Pioneer GitHub sync failed: #{result[:error]}"
        exit 1
      else
        puts "Pioneer GitHub sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Repositories: #{result[:repositories]}"
        puts "Developers: #{result[:developers]}"
        puts "Commits: #{result[:commits]}"
        puts "Pull Requests: #{result[:pull_requests]}"
      end
    end

    desc "Incremental sync of Pioneer GitHub data from the last day"
    task incremental_sync: :environment do
      puts "Starting incremental Pioneer GitHub data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["PIONEER_GITHUB_TOKEN"]
        puts "ERROR: PIONEER_GITHUB_TOKEN environment variable is required"
        exit 1
      end

      sync_service = Pioneer::GithubSyncService.new
      result = sync_service.sync_all_data(1.day.ago)

      if result[:error]
        puts "Pioneer GitHub sync failed: #{result[:error]}"
        exit 1
      else
        puts "Pioneer GitHub sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Repositories: #{result[:repositories]}"
        puts "Developers: #{result[:developers]}"
        puts "Commits: #{result[:commits]}"
        puts "Pull Requests: #{result[:pull_requests]}"
      end
    end
  end
end
