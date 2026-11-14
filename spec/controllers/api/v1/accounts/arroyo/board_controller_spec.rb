require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Arroyo::BoardController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Julieta', display_name: nil, email: 'juli@example.com') }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/arroyo/commercial/board" }
  let(:range) { { since: '2026-11-12', until: '2026-11-12' } }

  # Mediodía en Argentina: la fecha local y la UTC coinciden.
  before { travel_to Time.zone.parse('2026-11-12 15:00 UTC') }

  def configure(board: true)
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] }, funnel_board: { enabled: board })
    setting.save!
  end

  def inquiry
    conversation = create(:conversation, account: account, inbox: inbox, assignee: seller)
    create(:arroyo_opportunity, conversation: conversation, started_at: Time.current, state: 'pending')
  end

  it 'is forbidden while the panel funnel is off' do
    configure(board: false)
    get url, headers: admin.create_new_auth_token, params: range, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'shows the whole funnel to an agent of the account' do
    configure
    inquiry
    get url, headers: seller.create_new_auth_token, params: range

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('version' => 1, 'origin_level' => 'campaign')
    expect(response.parsed_body['totals']).to include('received' => 1, 'pending' => 1)
  end

  it 'rejects an unknown origin level' do
    configure
    get url, headers: admin.create_new_auth_token, params: range.merge(origin_level: 'adset')

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lists the inquiries of a node with their funnel stage' do
    configure
    record = inquiry
    get "#{url}/opportunities", headers: admin.create_new_auth_token, params: range.merge(bucket: seller.id.to_s, stage: 'pending')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['opportunities'].first).to include('id' => record.id, 'stage' => 'pending')
    expect(response.parsed_body['meta']).to eq('total' => 1, 'next_page' => nil)
  end

  it 'exports the table per day and seller' do
    configure
    inquiry
    get "#{url}/export", headers: admin.create_new_auth_token, params: range

    rows = CSV.parse(response.body)
    expect(rows.first.first(4)).to eq(%w[Date Seller Received Attended])
    expect(rows.last.first(4)).to eq(%w[2026-11-12 Julieta 1 0])
  end
end
