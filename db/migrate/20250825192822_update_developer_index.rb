class UpdateDeveloperIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :developers, :github_username
    remove_index :developers, :jira_username

    add_index :developers, [ :github_username, :app_type ], unique: true
    add_index :developers, [ :jira_username, :app_type ], unique: true
  end
end
