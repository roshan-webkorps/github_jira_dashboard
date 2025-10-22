class CreatePromptHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :prompt_histories do |t|
      t.string :ip_address, null: false
      t.string :app_type, null: false, default: "legacy"
      t.text :prompt, null: false
      t.timestamps
    end

    add_index :prompt_histories, [:ip_address, :prompt], unique: true
  end
end
