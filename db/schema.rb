# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_25_192822) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "commits", force: :cascade do |t|
    t.string "sha", null: false
    t.text "message"
    t.bigint "developer_id", null: false
    t.bigint "repository_id", null: false
    t.datetime "committed_at"
    t.integer "additions", default: 0
    t.integer "deletions", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_type", default: "legacy", null: false
    t.index ["app_type"], name: "index_commits_on_app_type"
    t.index ["committed_at"], name: "index_commits_on_committed_at"
    t.index ["developer_id"], name: "index_commits_on_developer_id"
    t.index ["repository_id"], name: "index_commits_on_repository_id"
    t.index ["sha"], name: "index_commits_on_sha", unique: true
    t.check_constraint "app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[])", name: "check_commit_type"
  end

  create_table "developers", force: :cascade do |t|
    t.string "name", null: false
    t.string "github_username"
    t.string "jira_username"
    t.string "email"
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_type", default: "legacy", null: false
    t.index ["app_type"], name: "index_developers_on_app_type"
    t.index ["github_username", "app_type"], name: "index_developers_on_github_username_and_app_type", unique: true
    t.index ["jira_username", "app_type"], name: "index_developers_on_jira_username_and_app_type", unique: true
    t.check_constraint "app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[])", name: "check_developer_type"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.integer "number", null: false
    t.string "title", null: false
    t.text "body"
    t.string "state", null: false
    t.bigint "developer_id", null: false
    t.bigint "repository_id", null: false
    t.string "github_id", null: false
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.datetime "merged_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_type", default: "legacy", null: false
    t.index ["app_type"], name: "index_pull_requests_on_app_type"
    t.index ["developer_id"], name: "index_pull_requests_on_developer_id"
    t.index ["github_id"], name: "index_pull_requests_on_github_id", unique: true
    t.index ["repository_id", "number"], name: "index_pull_requests_on_repository_id_and_number", unique: true
    t.index ["repository_id"], name: "index_pull_requests_on_repository_id"
    t.index ["state"], name: "index_pull_requests_on_state"
    t.check_constraint "app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[])", name: "check_pull_request_type"
  end

  create_table "repositories", force: :cascade do |t|
    t.string "name", null: false
    t.string "full_name", null: false
    t.string "owner", null: false
    t.text "description"
    t.string "language"
    t.string "github_id", null: false
    t.boolean "private", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_type", default: "legacy", null: false
    t.index ["app_type"], name: "index_repositories_on_app_type"
    t.index ["full_name"], name: "index_repositories_on_full_name", unique: true
    t.index ["github_id"], name: "index_repositories_on_github_id", unique: true
    t.check_constraint "app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[])", name: "check_repository_type"
  end

  create_table "tickets", force: :cascade do |t|
    t.string "key", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", null: false
    t.string "priority"
    t.string "ticket_type"
    t.bigint "developer_id"
    t.string "project_key"
    t.string "jira_id", null: false
    t.datetime "created_at_jira"
    t.datetime "updated_at_jira"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_type", default: "legacy", null: false
    t.index ["app_type"], name: "index_tickets_on_app_type"
    t.index ["developer_id"], name: "index_tickets_on_developer_id"
    t.index ["jira_id"], name: "index_tickets_on_jira_id", unique: true
    t.index ["key"], name: "index_tickets_on_key", unique: true
    t.index ["status"], name: "index_tickets_on_status"
    t.check_constraint "app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[])", name: "check_ticket_type"
  end

  add_foreign_key "commits", "developers"
  add_foreign_key "commits", "repositories"
  add_foreign_key "pull_requests", "developers"
  add_foreign_key "pull_requests", "repositories"
  add_foreign_key "tickets", "developers"
end
