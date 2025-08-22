env :PATH, ENV["PATH"]
set :environment, ENV["RAILS_ENV"]
set :output, "log/cron.log"

every 6.hours do
  rake "github:incremental_sync"
end

every 6.hours, at: "0:30" do
  rake "jira:incremental_sync"
end
