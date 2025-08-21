class CreateDevelopers < ActiveRecord::Migration[8.0]
  def change
    create_table :developers do |t|
      t.string :name, null: false
      t.string :github_username
      t.string :jira_username
      t.string :email
      t.string :avatar_url

      t.timestamps
    end

    add_index :developers, :github_username, unique: true
    add_index :developers, :jira_username, unique: true
  end
end
