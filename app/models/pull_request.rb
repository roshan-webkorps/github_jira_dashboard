# == Schema Information
#
# Table name: pull_requests
#
#  id            :bigint           not null, primary key
#  app_type      :string           default("legacy"), not null
#  body          :text
#  closed_at     :datetime
#  merged_at     :datetime
#  number        :integer          not null
#  opened_at     :datetime
#  state         :string           not null
#  title         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  developer_id  :bigint           not null
#  github_id     :string           not null
#  repository_id :bigint           not null
#
# Indexes
#
#  index_pull_requests_on_app_type                  (app_type)
#  index_pull_requests_on_developer_id              (developer_id)
#  index_pull_requests_on_github_id                 (github_id) UNIQUE
#  index_pull_requests_on_repository_id             (repository_id)
#  index_pull_requests_on_repository_id_and_number  (repository_id,number) UNIQUE
#  index_pull_requests_on_state                     (state)
#
# Foreign Keys
#
#  fk_rails_...  (developer_id => developers.id)
#  fk_rails_...  (repository_id => repositories.id)
#
class PullRequest < ApplicationRecord
  belongs_to :developer
  belongs_to :repository

  validates :number, presence: true
  validates :title, presence: true
  validates :state, presence: true, inclusion: { in: %w[open closed merged] }
  validates :github_id, presence: true, uniqueness: true
  validates :number, uniqueness: { scope: :repository_id }

  scope :open, -> { where(state: "open") }
  scope :closed, -> { where(state: "closed") }
  scope :merged, -> { where(state: "merged") }
  scope :recent, -> { where("opened_at > ?", 1.month.ago) }
end
