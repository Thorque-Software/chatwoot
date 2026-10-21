require 'rails_helper'
require 'rake'

RSpec.describe 'arroyo:commercial:enroll_followups', type: :task do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:task) { Rake::Task['arroyo:commercial:enroll_followups'] }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?('arroyo:commercial:enroll_followups')
    task.reenable
    travel_to zone.parse('2026-10-20 18:00')
    create(:message, account: account, conversation: conversation, message_type: :incoming)
    conversation.reload.update!(label_list: %w[seguimiento bici])
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] })
    setting.save!
  end

  it 'previews the original label date without enrolling or sending anything' do
    with_modified_env ACCOUNT_ID: account.id.to_s, CONVERSATION_IDS: conversation.display_id.to_s, APPLY: nil do
      expect { task.invoke }.to output(/"first_follow_up_at":"2026-10-21T10:00:00-03:00"/).to_stdout
    end
    expect(Arroyo::Opportunity.where(conversation: conversation)).not_to exist
    expect(conversation.reload.label_list).to match_array(%w[seguimiento bici])
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'applies only the named labelled conversation once without sending' do
    with_modified_env ACCOUNT_ID: account.id.to_s, CONVERSATION_IDS: conversation.display_id.to_s, APPLY: '1' do
      expect { task.invoke }.to output(/"enrolled":true/).to_stdout
      task.reenable
      expect { task.invoke }.to output(/"enrolled":true/).to_stdout
    end
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    expect(opportunity.events.where(kind: 'follow_up_enrolled').count).to eq(1)
    expect(conversation.messages.outgoing).to be_empty
  end
end
