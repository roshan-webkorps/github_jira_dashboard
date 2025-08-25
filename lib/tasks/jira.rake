namespace :jira do
  namespace :legacy do
    desc "Initial sync of Legacy Jira data for the last year"
    task initial_sync: :environment do
      puts "Starting initial Legacy Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["JIRA_URL"] && ENV["JIRA_USERNAME"] && ENV["JIRA_API_TOKEN"]
        puts "ERROR: JIRA_URL, JIRA_USERNAME, and JIRA_API_TOKEN environment variables are required"
        exit 1
      end

      sync_service = Legacy::JiraSyncService.new
      result = sync_service.sync_all_data(1.year.ago)

      if result[:error]
        puts "Legacy Jira sync failed: #{result[:error]}"
        exit 1
      else
        puts "Legacy Jira sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Total Legacy Tickets: #{result[:tickets]}"
        puts "Newly Synced: #{result[:synced_count]}"
      end
    end

    desc "Incremental sync of Legacy Jira data from the last day"
    task incremental_sync: :environment do
      puts "Starting incremental Legacy Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["JIRA_URL"] && ENV["JIRA_USERNAME"] && ENV["JIRA_API_TOKEN"]
        puts "ERROR: JIRA_URL, JIRA_USERNAME, and JIRA_API_TOKEN environment variables are required"
        exit 1
      end

      sync_service = Legacy::JiraSyncService.new
      result = sync_service.sync_all_data(1.day.ago)

      if result[:error]
        puts "Legacy Jira sync failed: #{result[:error]}"
        exit 1
      else
        puts "Legacy Jira sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Total Legacy Tickets: #{result[:tickets]}"
        puts "Newly Synced: #{result[:synced_count]}"
      end
    end
  end

  namespace :pioneer do
    desc "Initial sync of Pioneer Jira data for the last year"
    task initial_sync: :environment do
      puts "Starting initial Pioneer Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["PIONEER_JIRA_URL"] && ENV["PIONEER_JIRA_USERNAME"] && ENV["PIONEER_JIRA_API_TOKEN"]
        puts "ERROR: PIONEER_JIRA_URL, PIONEER_JIRA_USERNAME, and PIONEER_JIRA_API_TOKEN environment variables are required"
        exit 1
      end

      sync_service = Pioneer::JiraSyncService.new
      result = sync_service.sync_all_data(1.year.ago)

      if result[:error]
        puts "Pioneer Jira sync failed: #{result[:error]}"
        exit 1
      else
        puts "Pioneer Jira sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Total Pioneer Tickets: #{result[:tickets]}"
        puts "Newly Synced: #{result[:synced_count]}"
      end
    end

    desc "Incremental sync of Pioneer Jira data from the last day"
    task incremental_sync: :environment do
      puts "Starting incremental Pioneer Jira data sync at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}..."

      unless ENV["PIONEER_JIRA_URL"] && ENV["PIONEER_JIRA_USERNAME"] && ENV["PIONEER_JIRA_API_TOKEN"]
        puts "ERROR: PIONEER_JIRA_URL, PIONEER_JIRA_USERNAME, and PIONEER_JIRA_API_TOKEN environment variables are required"
        exit 1
      end

      sync_service = Pioneer::JiraSyncService.new
      result = sync_service.sync_all_data(1.day.ago)

      if result[:error]
        puts "Pioneer Jira sync failed: #{result[:error]}"
        exit 1
      else
        puts "Pioneer Jira sync completed successfully at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}!"
        puts "Total Pioneer Tickets: #{result[:tickets]}"
        puts "Newly Synced: #{result[:synced_count]}"
      end
    end
  end
end
