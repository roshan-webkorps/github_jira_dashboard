namespace :jira do
  desc "Initial sync of Jira data for the last year"
  task initial_sync: :environment do
    puts "Starting initial Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

    unless ENV["JIRA_URL"] && ENV["JIRA_USERNAME"] && ENV["JIRA_API_TOKEN"]
      puts "ERROR: JIRA_URL, JIRA_USERNAME, and JIRA_API_TOKEN environment variables are required"
      exit 1
    end

    sync_service = JiraSyncService.new
    result = sync_service.sync_all_data(1.year.ago)

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
      puts "Total Tickets: #{result[:tickets]}"
      puts "Newly Synced: #{result[:synced_count]}"
    end
  end

  desc "Incremental sync of Jira data from the last day"
  task incremental_sync: :environment do
    puts "Starting incremental Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

    unless ENV["JIRA_URL"] && ENV["JIRA_USERNAME"] && ENV["JIRA_API_TOKEN"]
      puts "ERROR: JIRA_URL, JIRA_USERNAME, and JIRA_API_TOKEN environment variables are required"
      exit 1
    end

    sync_service = JiraSyncService.new
    result = sync_service.sync_all_data(1.day.ago)

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
      puts "Total Tickets: #{result[:tickets]}"
      puts "Newly Synced: #{result[:synced_count]}"
    end
  end
end
