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
    channel.update!(message_templates: [{ 'name' => 'seg_dia_1', 'language' => 'es_AR', 'status' => 'APPROVED',
                                          'components' => [{ 'type' => 'BODY', 'text' => '{{asesor}} {{producto}}' }], 'secret' => 'must-not-leak' }])
    get "#{url}/purchases", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['purchases'].first['inbox'].keys).to match_array(%w[id channel_type message_templates])
    expect(response.parsed_body.to_json).not_to include('test_key', 'provider_config', 'must-not-leak')
    expect(response.parsed_body.dig('config', 'commercial_templates', channel.inbox.id.to_s).first['name']).to eq('seg_dia_1')
    expect(response.parsed_body.dig('config', 'stages', 'd1', 'free_text')).to eq('')
  end

  it 'accepts a revision without a configurable body and creates the approved template' do
    channel.update!(message_templates: [{ 'name' => 'postventa_d1', 'language' => 'es_AR', 'status' => 'APPROVED',
                                          'parameter_format' => 'NAMED', 'category' => 'MARKETING',
                                          'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{asesor}}, {{producto}}' }] }])
    purchase = Arroyo::PostSalePurchase.find_by!(conversation: conversation)
    purchase.update!(planned_revision: purchase.revision)
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    follow_up.update!(status: 'scheduled', scheduled_at: Time.current)
    post "#{url}/follow_ups/#{follow_up.id}/message", headers: admin.create_new_auth_token,
                                                      params: { revision: 1, content: 'Ignore me' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(follow_up.reload.message.content).to eq("Hola #{agent.available_name}, #{purchase.product}")
    expect(follow_up.channel_used).to eq('template')
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
    foreign_purchase = Arroyo::PostSale::RegisterPurchaseService.new(conversation: foreign_conversation.reload, timestamp: Time.current).perform

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

  it 'filters manual tasks without losing overview totals and prioritizes pending work' do
    purchase = Arroyo::PostSalePurchase.find_by!(conversation: conversation)
    pending = purchase.follow_ups.find_by!(stage: 'd7')
    pending.update!(status: 'failed', manual_status: 'pending', alert_assignee: agent)
    delivered = purchase.follow_ups.find_by!(stage: 'd30')
    delivered.update!(status: 'delivered')

    get "#{url}/follow_ups", headers: agent.create_new_auth_token
    expect(response.parsed_body['follow_ups'].first['id']).to eq(pending.id)

    get "#{url}/follow_ups", headers: agent.create_new_auth_token, params: { manual_status: 'pending' }
    expect(response.parsed_body['follow_ups'].pluck('id')).to eq([pending.id])
    expect(response.parsed_body['totals']).to include('manual_pending' => 1, 'delivered' => 1)

    get "#{url}/follow_ups", headers: other.create_new_auth_token, params: { manual_status: 'pending' }
    expect(response.parsed_body['follow_ups']).to be_empty
    expect(response.parsed_body['totals']['manual_pending']).to eq(0)
  end

  it 'filters stages before pagination and counts only stages visible to the user' do
    purchase = Arroyo::PostSalePurchase.find_by!(conversation: conversation)
    follow_up = purchase.follow_ups.find_by!(stage: 'd7')
    follow_up.update!(status: 'failed', manual_status: 'pending', alert_assignee: agent)

    %w[d1 d7 d30].each do |stage|
      get "#{url}/follow_ups", headers: agent.create_new_auth_token, params: { stage: stage }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['follow_ups'].pluck('stage')).to eq([stage])
      expect(response.parsed_body['meta']['total']).to eq(1)
      expect(response.parsed_body['totals'].except('manual_pending').values.sum).to eq(1)
    end

    get "#{url}/follow_ups", headers: agent.create_new_auth_token,
                             params: { stage: 'd7', status: 'failed', manual_status: 'pending' }
    expect(response.parsed_body['follow_ups'].pluck('id')).to eq([follow_up.id])
    expect(response.parsed_body['totals']).to eq('failed' => 1, 'manual_pending' => 1)
  end

  it 'keeps stage-filtered results and totals restricted to the authorized seller or alert assignee' do
    get "#{url}/follow_ups", headers: other.create_new_auth_token, params: { stage: 'd7' }
    expect(response.parsed_body['follow_ups']).to be_empty
    expect(response.parsed_body['meta']['total']).to eq(0)
    expect(response.parsed_body['totals']).to eq('manual_pending' => 0)
  end
end
