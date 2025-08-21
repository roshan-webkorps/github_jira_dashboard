class CreateTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :tickets do |t|
      t.string :key, null: false
      t.string :title, null: false
      t.text :description
      t.string :status, null: false
      t.string :priority
      t.string :ticket_type
      t.references :developer, null: true, foreign_key: true
      t.string :project_key
      t.string :jira_id, null: false
      t.datetime :created_at_jira
      t.datetime :updated_at_jira

      t.timestamps
    end

    add_index :tickets, :jira_id, unique: true
    add_index :tickets, :key, unique: true
    add_index :tickets, :status
  end
end
