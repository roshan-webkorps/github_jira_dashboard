# == Schema Information
#
# Table name: tickets
#
#  id              :bigint           not null, primary key
#  app_type        :string           default("legacy"), not null
#  created_at_jira :datetime
#  description     :text
#  key             :string           not null
#  priority        :string
#  project_key     :string
#  status          :string           not null
#  ticket_type     :string
#  title           :string           not null
#  updated_at_jira :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  developer_id    :bigint
#  jira_id         :string           not null
#
# Indexes
#
#  index_tickets_on_app_type      (app_type)
#  index_tickets_on_developer_id  (developer_id)
#  index_tickets_on_jira_id       (jira_id) UNIQUE
#  index_tickets_on_key           (key) UNIQUE
#  index_tickets_on_status        (status)
#
# Foreign Keys
#
#  fk_rails_...  (developer_id => developers.id)
#
# Check Constraints
#
#  check_ticket_type  (app_type::text = ANY (ARRAY['legacy'::character varying, 'pioneer'::character varying]::text[]))
#
class Ticket < ApplicationRecord
  belongs_to :developer, optional: true

  validates :key, presence: true, uniqueness: true
  validates :title, presence: true
  validates :status, presence: true
  validates :jira_id, presence: true, uniqueness: true

  scope :open, -> { where.not(status: [ "Done", "Closed", "Resolved" ]) }
  scope :closed, -> { where(status: [ "Done", "Closed", "Resolved" ]) }
  scope :recent, -> { where("created_at_jira > ?", 1.month.ago) }
end
