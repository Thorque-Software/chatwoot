FactoryBot.define do
  factory :arroyo_opportunity, class: 'Arroyo::Opportunity' do
    conversation
    account { conversation.account }
    contact { conversation.contact }
    inbox { conversation.inbox }
    assignee { conversation.assignee }
    first_assignee { conversation.assignee }
    reference { SecureRandom.uuid }
    state { 'in_progress' }
    started_at { 1.day.ago }
  end
end
