require 'rails_helper'

RSpec.describe 'Arroyo commercial API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/arroyo/commercial" }
  let(:dates) { { since: '2026-10-20', until: '2026-10-20' } }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, balanced_assignment_enabled: true,
                                        seller_ids: [seller.id, other.id] })
    setting.save!
    create(:inbox_member, inbox: inbox, user: seller)
    create(:inbox_member, inbox: inbox, user: other)
  end

  def incoming(user, at: zone.parse('2026-10-20 09:00'))
    conversation = create(:conversation, account: account, inbox: inbox, assignee: user)
    create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: at)
    conversation
  end

  it 'keeps cohort and actual activity separate with deduplicated totals' do
    old = incoming(seller, at: zone.parse('2026-10-19 09:00'))
    create(:message, account: account, conversation: old, sender: seller, message_type: :outgoing, created_at: zone.parse('2026-10-20 09:00'))
    incoming(other)
    get "#{base}/report", params: dates, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('totals', 'received')).to eq(1)
    expect(response.parsed_body.dig('activity_totals', 'attended')).to eq(1)
    expect(response.parsed_body['series'].first['date']).to eq('2026-10-20')
  end

  it 'restricts the whole response and the detail to own permitted opportunities' do
    mine = incoming(seller)
    theirs = incoming(other)
    headers = seller.create_new_auth_token
    get "#{base}/report", params: dates.merge(user_ids: [other.id]), headers: headers
    expect(response.parsed_body.dig('totals', 'received')).to eq(1)
    expect(response.parsed_body['agents'].map { |agent| agent['id'] }).to eq([seller.id])
    get "#{base}/opportunities", params: dates, headers: headers
    expect(response.parsed_body['opportunities'].map { |item| item.dig('conversation', 'display_id') }).to eq([mine.display_id])
    patch "#{base}/opportunities/#{Arroyo::Opportunity.find_by!(conversation: theirs).id}",
          params: { outcome: 'won' }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not rebalance a manually assigned conversation and returns its actual assignee' do
    conversation = incoming(other)
    post "#{base}/assign", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('assignee_id' => other.id, 'assigned' => false)
    expect(conversation.reload.assignee_id).to eq(other.id)
  end

  it 'counts manual acquisitions and transfers when choosing the next agent' do
    3.times { incoming(other, at: Time.current) }
    conversation = incoming(nil, at: Time.current)
    post "#{base}/assign", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['assignee_id']).to eq(seller.id)
    expect(Arroyo::Opportunity.find_by!(conversation: conversation).events.where(kind: 'assigned').last.origin).to eq('automation')
    post "#{base}/assign", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    expect(response.parsed_body['assigned']).to be(false)
    expect(conversation.reload.assignee_id).to eq(seller.id)
  end

  it 'protects integration context and publishes flags without private data when disabled' do
    get "#{base}/contexts", headers: seller.create_new_auth_token
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    get "#{base}/contexts", headers: admin.create_new_auth_token
    expect(response.parsed_body.dig('config', 'funnel_enabled')).to be(true)
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false, balanced_assignment_enabled: false })
    setting.save!
    get "#{base}/contexts", headers: admin.create_new_auth_token
    expect(response.parsed_body['contexts']).to eq([])
    get "#{base}/report", params: dates, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'exports the selected opportunity list instead of unrelated report totals' do
    mine = incoming(seller)
    incoming(other)
    get "#{base}/export", params: dates.merge(metric: 'pending', scope: 'cohort', user_ids: [seller.id]), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(mine.display_id.to_s, mine.contact.name)
    expect(response.body).not_to include('report.totals')
    expect(CSV.parse(response.body).size).to eq(2)
  end

  it 'keeps the seller-filtered received chart and its drilldown equal' do
    incoming(seller)
    incoming(other)
    filters = dates.merge(user_ids: [seller.id])
    headers = admin.create_new_auth_token
    get "#{base}/report", params: filters, headers: headers
    expect(response.parsed_body.dig('activity_totals', 'received')).to eq(1)
    get "#{base}/opportunities", params: filters.merge(metric: 'received', scope: 'activity'), headers: headers
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
  end

  it 'keeps the commercial owner when an administrator records the sale' do
    conversation = incoming(seller, at: Time.current)
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    headers = admin.create_new_auth_token
    patch "#{base}/opportunities/#{opportunity.id}", params: { outcome: 'won' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(opportunity.reload.result_user_id).to eq(seller.id)
    expect(opportunity.events.find_by!(kind: 'won').actor_id).to eq(admin.id)
    today = Time.current.in_time_zone(zone).to_date.iso8601
    get "#{base}/report", params: { since: today, until: today, user_ids: [seller.id] }, headers: headers
    expect(response.parsed_body.dig('activity_totals', 'won')).to eq(1)
    expect(response.parsed_body['agents'].first.dig('periods', today, 'won')).to eq(1)
  end
end
