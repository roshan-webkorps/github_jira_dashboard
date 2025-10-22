# == Schema Information
#
# Table name: prompt_histories
#
#  id         :bigint           not null, primary key
#  app_type   :string           default("legacy"), not null
#  ip_address :string           not null
#  prompt     :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_prompt_histories_on_ip_address_and_prompt  (ip_address,prompt) UNIQUE
#
class PromptHistory < ApplicationRecord
end
