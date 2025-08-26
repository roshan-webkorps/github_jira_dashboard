# == Schema Information
#
# Table name: commits
#
#  id            :bigint           not null, primary key
#  additions     :integer          default(0)
#  app_type      :string           default("legacy"), not null
#  committed_at  :datetime
#  deletions     :integer          default(0)
#  message       :text
#  sha           :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  developer_id  :bigint           not null
#  repository_id :bigint           not null
#
# Indexes
#
#  index_commits_on_app_type       (app_type)
#  index_commits_on_committed_at   (committed_at)
#  index_commits_on_developer_id   (developer_id)
#  index_commits_on_repository_id  (repository_id)
#  index_commits_on_sha            (sha) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (developer_id => developers.id)
#  fk_rails_...  (repository_id => repositories.id)
#
class Commit < ApplicationRecord
  belongs_to :developer
  belongs_to :repository

  validates :sha, presence: true, uniqueness: true
  validates :committed_at, presence: true

  scope :recent, -> { where("committed_at > ?", 1.month.ago) }
  scope :by_developer, ->(dev_id) { where(developer_id: dev_id) }
end
