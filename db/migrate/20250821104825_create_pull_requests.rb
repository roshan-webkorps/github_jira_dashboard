class CreatePullRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_requests do |t|
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body
      t.string :state, null: false # open, closed, merged
      t.references :developer, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.string :github_id, null: false
      t.datetime :opened_at
      t.datetime :closed_at
      t.datetime :merged_at

      t.timestamps
    end

    add_index :pull_requests, :github_id, unique: true
    add_index :pull_requests, [ :repository_id, :number ], unique: true
    add_index :pull_requests, :state
  end
end
