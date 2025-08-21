class CreateCommits < ActiveRecord::Migration[8.0]
  def change
    create_table :commits do |t|
      t.string :sha, null: false
      t.text :message
      t.references :developer, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.datetime :committed_at
      t.integer :additions, default: 0
      t.integer :deletions, default: 0

      t.timestamps
    end

    add_index :commits, :sha, unique: true
    add_index :commits, :committed_at
  end
end
