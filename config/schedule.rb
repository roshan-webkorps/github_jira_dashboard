env :PATH, ENV["PATH"]
set :environment, ENV["RAILS_ENV"]
set :output, "log/cron.log"

# Legacy app syncs
every 6.hours do
  rake "github:legacy:incremental_sync"
end

every 6.hours, at: "0:30" do
  rake "jira:legacy:incremental_sync"
end

# Pioneer app syncs - offset by 2 hours to spread load
every 6.hours, at: "2:00" do
  rake "github:pioneer:incremental_sync"
end

every 6.hours, at: "2:30" do
  rake "jira:pioneer:incremental_sync"
end
