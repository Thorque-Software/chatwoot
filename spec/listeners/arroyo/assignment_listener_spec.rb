require 'rails_helper'

RSpec.describe Arroyo::AssignmentListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'records the assignment with the assignee from the event' do
    event = Events::Base.new('assignee.changed', Time.zone.now,
                             conversation: conversation, changed_attributes: { 'assignee_id' => [nil, agent.id] })

    expect { listener.assignee_changed(event) }.to change(Arroyo::AssignmentEvent, :count).by(1)
    expect(Arroyo::AssignmentEvent.last).to have_attributes(account_id: account.id, conversation_id: conversation.id,
                                                            inbox_id: conversation.inbox_id, assignee_id: agent.id)
  end

  it 'ignores unassignments' do
    event = Events::Base.new('assignee.changed', Time.zone.now,
                             conversation: conversation, changed_attributes: { 'assignee_id' => [agent.id, nil] })

    expect { listener.assignee_changed(event) }.not_to change(Arroyo::AssignmentEvent, :count)
  end

  it 'is registered in the async dispatcher' do
    expect(AsyncDispatcher.new.listeners.map { |item| item.class.name }).to include(described_class.name)
  end
end
