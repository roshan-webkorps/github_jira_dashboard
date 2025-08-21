namespace :jira do
  desc "Sync all Jira data (issues/tickets)"
  task sync: :environment do
    puts "Starting Jira data sync..."
    
    unless ENV['JIRA_URL'] && ENV['JIRA_USERNAME'] && ENV['JIRA_API_TOKEN']
      puts "ERROR: JIRA_URL, JIRA_USERNAME, and JIRA_API_TOKEN environment variables are required"
      exit 1
    end

    sync_service = JiraSyncService.new
    result = sync_service.sync_all_data

    if result[:error]
      puts "Sync failed: #{result[:error]}"
      exit 1
    else
      puts "Sync completed successfully!"
      puts "Summary:"
      puts "  - Total Tickets: #{result[:tickets]}"
      puts "  - Newly Synced: #{result[:synced_count]}"
    end
  end
end
