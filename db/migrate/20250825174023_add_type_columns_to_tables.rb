class AddTypeColumnsToTables < ActiveRecord::Migration[8.0]
  def change
    # Add app_type column to developers table
    add_column :developers, :app_type, :string, default: 'legacy', null: false
    add_index :developers, :app_type

    # Add app_type column to repositories table
    add_column :repositories, :app_type, :string, default: 'legacy', null: false
    add_index :repositories, :app_type

    # Add app_type column to commits table
    add_column :commits, :app_type, :string, default: 'legacy', null: false
    add_index :commits, :app_type

    # Add app_type column to pull_requests table
    add_column :pull_requests, :app_type, :string, default: 'legacy', null: false
    add_index :pull_requests, :app_type

    # Add app_type column to tickets table
    add_column :tickets, :app_type, :string, default: 'legacy', null: false
    add_index :tickets, :app_type

    # Add constraints to ensure valid values
    add_check_constraint :developers, "app_type IN ('legacy', 'pioneer')", name: 'check_developer_type'
    add_check_constraint :repositories, "app_type IN ('legacy', 'pioneer')", name: 'check_repository_type'
    add_check_constraint :commits, "app_type IN ('legacy', 'pioneer')", name: 'check_commit_type'
    add_check_constraint :pull_requests, "app_type IN ('legacy', 'pioneer')", name: 'check_pull_request_type'
    add_check_constraint :tickets, "app_type IN ('legacy', 'pioneer')", name: 'check_ticket_type'
  end

  def down
    # Remove constraints first
    remove_check_constraint :developers, name: 'check_developer_type'
    remove_check_constraint :repositories, name: 'check_repository_type'
    remove_check_constraint :commits, name: 'check_commit_type'
    remove_check_constraint :pull_requests, name: 'check_pull_request_type'
    remove_check_constraint :tickets, name: 'check_ticket_type'

    # Remove indexes
    remove_index :developers, :app_type
    remove_index :repositories, :app_type
    remove_index :commits, :app_type
    remove_index :pull_requests, :app_type
    remove_index :tickets, :app_type

    # Remove columns
    remove_column :developers, :app_type
    remove_column :repositories, :app_type
    remove_column :commits, :app_type
    remove_column :pull_requests, :app_type
    remove_column :tickets, :app_type
  end
end
