require 'rails_helper'

RSpec.describe Arroyo::Ads::CampaignResolverJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, additional_attributes: { 'ad_source' => 'whatsapp_ad', 'ad_id' => '123' }) }
  let(:names) { { 'ad_name' => 'Video 1', 'ad_campaign_name' => 'Verano 2026' } }

  before { Rails.cache.clear }

  def save_token(token)
    setting = Arroyo::Setting.for(account)
    setting.meta_ads_token = token
    setting.save!
  end

  it 'adds the campaign names to the conversation' do
    save_token('secret-token')
    lookup = instance_double(Arroyo::Ads::CampaignLookupService, perform: names)
    allow(Arroyo::Ads::CampaignLookupService).to receive(:new).with(token: 'secret-token', ad_id: '123').and_return(lookup)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.additional_attributes).to include('ad_id' => '123', 'ad_campaign_name' => 'Verano 2026')
  end

  it 'does nothing without a token' do
    allow(Arroyo::Ads::CampaignLookupService).to receive(:new)

    described_class.perform_now(conversation.id)

    expect(Arroyo::Ads::CampaignLookupService).not_to have_received(:new)
  end
end
