require 'rails_helper'

RSpec.describe Arroyo::Ads::CampaignLookupService do
  subject(:lookup) { described_class.new(token: 'secret-token', ad_id: '120210000000000') }

  let(:url) { 'https://graph.facebook.com/v22.0/120210000000000' }

  def stub_graph(status:, body:)
    stub_request(:get, url).with(query: { fields: described_class::FIELDS }, headers: { 'Authorization' => 'Bearer secret-token' })
                           .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'returns the ad, ad set and campaign names' do
    stub_graph(status: 200, body: { id: '120210000000000', name: 'Video 1', adset: { id: '2', name: 'Mujeres 25-35' },
                                    campaign: { id: '3', name: 'Verano 2026' } })

    expect(lookup.perform).to eq(
      'ad_name' => 'Video 1', 'ad_adset_id' => '2', 'ad_adset_name' => 'Mujeres 25-35',
      'ad_campaign_id' => '3', 'ad_campaign_name' => 'Verano 2026'
    )
  end

  it 'raises with the Meta message when the token is rejected' do
    stub_graph(status: 400, body: { error: { message: 'Invalid OAuth access token.', code: 190 } })

    expect { lookup.perform }.to raise_error(Arroyo::Ads::LookupError, 'Invalid OAuth access token.')
  end
end
