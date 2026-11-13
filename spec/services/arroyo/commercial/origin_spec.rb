require 'rails_helper'

RSpec.describe Arroyo::Commercial::Origin do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:opportunity) { create(:arroyo_opportunity, conversation: conversation, started_at: Time.zone.parse('2026-11-10 10:00')) }

  def capture(attributes)
    conversation.update!(additional_attributes: attributes)
    described_class.new(opportunity: opportunity, conversation: conversation).capture
    opportunity.reload.origin
  end

  it 'copies the ad that arrived with the inquiry, without its body or click id' do
    origin = capture('ad_id' => '52615', 'ad_name' => 'Reel Bici', 'ad_campaign_name' => 'Bicis Rosario', 'ad_body' => 'Texto largo',
                     'ad_ctwa_clid' => 'Af1', 'ad_referral_at' => '2026-11-10T09:59:58Z')

    expect(origin).to eq('ad_id' => '52615', 'ad_name' => 'Reel Bici', 'ad_campaign_name' => 'Bicis Rosario')
  end

  it 'does not give an old ad of the conversation to a later inquiry' do
    expect(capture('ad_id' => '52615', 'ad_referral_at' => '2026-11-01T10:00:00Z')).to eq({})
  end

  it 'leaves organic inquiries and ads without a time stamp empty' do
    expect(capture('browser_language' => 'es')).to eq({})
    expect(capture('ad_id' => '52615')).to eq({})
    expect(described_class.organic?(opportunity.origin)).to be(true)
  end

  it 'keeps the first origin of the inquiry' do
    capture('ad_id' => 'first', 'ad_referral_at' => '2026-11-10T10:00:00Z')

    expect(capture('ad_id' => 'second', 'ad_referral_at' => '2026-11-10T11:00:00Z')).to eq('ad_id' => 'first')
  end
end
