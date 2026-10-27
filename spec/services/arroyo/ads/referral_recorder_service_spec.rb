require 'rails_helper'

RSpec.describe Arroyo::Ads::ReferralRecorderService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, additional_attributes: { 'browser_language' => 'es' }) }
  let(:referral) do
    {
      source_url: 'https://fb.me/abc', source_id: '120210000000000', source_type: 'ad',
      headline: 'Verano 2026', body: 'Probá una clase gratis', media_type: 'image', ctwa_clid: 'AfX123',
      image_url: 'https://scontent.example/img.jpg'
    }
  end
  let(:message) { { id: 'wamid.1', type: 'text', referral: referral }.with_indifferent_access }

  def enable_feature
    setting = Arroyo::Setting.for(account)
    setting.merge_config(ads_attribution: { enabled: true })
    setting.save!
  end

  def record(message_data = message)
    described_class.new(conversation: conversation, message: message_data).perform
    conversation.reload.additional_attributes
  end

  context 'when the feature is enabled' do
    before { enable_feature }

    it 'stores the referral data next to the existing attributes' do
      expect(record).to include(
        'browser_language' => 'es', 'ad_source' => 'whatsapp_ad', 'ad_id' => '120210000000000', 'ad_source_type' => 'ad',
        'ad_source_url' => 'https://fb.me/abc', 'ad_headline' => 'Verano 2026', 'ad_body' => 'Probá una clase gratis',
        'ad_media_type' => 'image', 'ad_ctwa_clid' => 'AfX123'
      )
    end

    it 'does not store the expiring media urls' do
      expect(record.keys).not_to include('image_url', 'ad_image_url')
    end

    it 'skips fields Meta did not send' do
      attrs = record({ referral: { source_id: '1' } }.with_indifferent_access)

      expect(attrs).to include('ad_id' => '1')
      expect(attrs.keys).not_to include('ad_headline')
    end

    it 'does not look up the campaign without a token' do
      expect { record }.not_to have_enqueued_job(Arroyo::Ads::CampaignResolverJob)
    end

    it 'looks up the campaign when the account has a token' do
      setting = Arroyo::Setting.for(account)
      setting.meta_ads_token = 'secret-token'
      setting.save!

      expect { record }.to have_enqueued_job(Arroyo::Ads::CampaignResolverJob).with(conversation.id)
    end

    it 'does nothing for a message without referral' do
      expect(record({ id: 'wamid.2', type: 'text' }.with_indifferent_access)).to eq('browser_language' => 'es')
    end
  end

  context 'when the feature is disabled' do
    it 'leaves the conversation untouched' do
      expect(record).to eq('browser_language' => 'es')
    end
  end

  describe 'through the WhatsApp Cloud webhook' do
    let!(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:params) do
      {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Lead Ads' }, wa_id: '5491122334455' }],
          messages: [{ from: '5491122334455', id: 'wamid.ads1', timestamp: '1664799904', type: 'text',
                       text: { body: 'Hola, quiero info' }, referral: referral }]
        } }] }]
      }.with_indifferent_access
    end

    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    it 'records the ad on the new conversation when the feature is enabled' do
      enable_feature
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform

      expect(channel.inbox.conversations.last.additional_attributes).to include('ad_source' => 'whatsapp_ad', 'ad_id' => '120210000000000')
    end

    it 'does not record the ad when the feature is disabled' do
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform

      expect(channel.inbox.conversations.last.additional_attributes).not_to include('ad_id')
    end
  end
end
