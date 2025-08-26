# == Schema Information
#
# Table name: developers
#
#  id              :bigint           not null, primary key
#  app_type        :string           default("legacy"), not null
#  avatar_url      :string
#  email           :string
#  github_username :string
#  jira_username   :string
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_developers_on_app_type                      (app_type)
#  index_developers_on_github_username_and_app_type  (github_username,app_type) UNIQUE
#  index_developers_on_jira_username_and_app_type    (jira_username,app_type) UNIQUE
#
class Developer < ApplicationRecord
  has_many :commits, dependent: :destroy
  has_many :pull_requests, dependent: :destroy
  has_many :tickets, dependent: :destroy

  validates :name, presence: true
  validates :github_username, uniqueness: true, allow_blank: true
  validates :jira_username, uniqueness: true, allow_blank: true
end
