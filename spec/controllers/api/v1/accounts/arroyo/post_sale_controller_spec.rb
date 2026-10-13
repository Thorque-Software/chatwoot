require 'rails_helper'

RSpec.describe 'Arroyo post-sale API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/arroyo/post_sale" }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(post_sale: { enabled: true, alert_user_ids: [admin.id] }, agent_panel: { enabled: true })
    setting.save!
    conversation.update!(label_list: ['vendido'])
  end

  it 'rejects unauthenticated requests and admin integration access by an agent' do
    get "#{url}/purchases"
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/purchases", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'restricts the panel to the seller or alert assignee even when activity visibility permits all agents' do
    Arroyo::Setting.for(account).tap { |setting| setting.merge_config(agent_panel: { agents_see_only_own: false }) }.save!
    get "#{url}/follow_ups", headers: other.create_new_auth_token
    expect(response.parsed_body['follow_ups']).to be_empty
    get "#{url}/follow_ups", headers: agent.create_new_auth_token
    expect(response.parsed_body['follow_ups'].size).to eq(3)
    expect(response.parsed_body['follow_ups'].first.dig('purchase', 'can_edit_purchase')).to be(true)
  end

  it 'returns only allowlisted channel metadata for n8n, without credentials' do
    get "#{url}/purchases", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['purchases'].first['inbox'].keys).to match_array(%w[id channel_type message_templates])
    expect(response.parsed_body.to_json).not_to include('test_key', 'provider_config')
  end

  it 'requires a current revision and audits correction' do
    purchase = Arroyo::PostSalePurchase.find_by!(conversation: conversation)
    patch "#{url}/purchases/#{purchase.reference}", headers: agent.create_new_auth_token,
                                                    params: { purchased_at: '2026-10-12T15:00:00-03:00' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(purchase.reload.revision).to eq(2)
    expect(purchase.date_changes.last['user_id']).to eq(agent.id)

    put "#{url}/purchases/#{purchase.reference}/plan", headers: admin.create_new_auth_token,
                                                       params: { revision: 1, stages: { d1: '2026-10-13T10:00:00-03:00' } }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'never returns or mutates a purchase from another account' do
    foreign_account = create(:account)
    foreign_channel = create(:channel_whatsapp, account: foreign_account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false)
    foreign_conversation = create(:conversation, account: foreign_account, inbox: foreign_channel.inbox, label_list: ['vendido'])
    foreign_purchase = Arroyo::PostSale::RegisterPurchaseService.new(conversation: foreign_conversation, timestamp: Time.current).perform

    get "#{url}/follow_ups", headers: admin.create_new_auth_token, params: { purchase_reference: foreign_purchase.reference }
    expect(response.parsed_body['follow_ups']).to be_empty
    patch "#{url}/purchases/#{foreign_purchase.reference}", headers: admin.create_new_auth_token,
                                                            params: { purchased_at: 1.day.ago.iso8601 }, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{url}/follow_ups/#{foreign_purchase.follow_ups.first.id}/message", headers: admin.create_new_auth_token,
                                                                              params: { revision: 1, content: 'Follow-up' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign_purchase.reload.revision).to eq(1)
  end

  it 'rejects new messages when disabled but retains an inspectable history' do
    follow_up = Arroyo::PostSalePurchase.find_by!(conversation: conversation).follow_ups.first
    Arroyo::Setting.for(account).tap { |setting| setting.merge_config(post_sale: { enabled: false }) }.save!
    post "#{url}/follow_ups/#{follow_up.id}/message", headers: admin.create_new_auth_token,
                                                      params: { revision: 1, content: 'Follow-up' }, as: :json
    expect(response).to have_http_status(:forbidden)
    get "#{url}/follow_ups", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end
end
