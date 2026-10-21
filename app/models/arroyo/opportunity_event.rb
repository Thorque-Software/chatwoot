class Arroyo::OpportunityEvent < ApplicationRecord
  belongs_to :opportunity, class_name: 'Arroyo::Opportunity', inverse_of: :events
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :message, optional: true
  validates :kind, :source_key, :origin, :occurred_at, presence: true
  validates :source_key, uniqueness: { scope: :opportunity_id }
end
