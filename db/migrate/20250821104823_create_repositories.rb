class CreateRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :repositories do |t|
      t.string :name, null: false
      t.string :full_name, null: false
      t.string :owner, null: false
      t.text :description
      t.string :language
      t.string :github_id, null: false
      t.boolean :private, default: false

      t.timestamps
    end

    add_index :repositories, :github_id, unique: true
    add_index :repositories, :full_name, unique: true
  end
end
