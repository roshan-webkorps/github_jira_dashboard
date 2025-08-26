# == Schema Information
#
# Table name: repositories
#
#  id          :bigint           not null, primary key
#  app_type    :string           default("legacy"), not null
#  description :text
#  full_name   :string           not null
#  language    :string
#  name        :string           not null
#  owner       :string           not null
#  private     :boolean          default(FALSE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  github_id   :string           not null
#
# Indexes
#
#  index_repositories_on_app_type   (app_type)
#  index_repositories_on_full_name  (full_name) UNIQUE
#  index_repositories_on_github_id  (github_id) UNIQUE
#
class Repository < ApplicationRecord
  has_many :commits, dependent: :destroy
  has_many :pull_requests, dependent: :destroy

  validates :name, presence: true
  validates :full_name, presence: true, uniqueness: true
  validates :owner, presence: true
  validates :github_id, presence: true, uniqueness: true
end
