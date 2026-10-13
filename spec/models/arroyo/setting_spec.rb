require 'rails_helper'

RSpec.describe Arroyo::Setting do
  let(:account) { create(:account) }
  let(:setting) { described_class.for(account) }

  describe '.for' do
    it 'builds a record with the defaults when the account has none' do
      expect(setting).to be_new_record
      expect(setting.config).to eq(described_class::DEFAULTS)
    end

    it 'returns the saved record of the account' do
      setting.save!

      expect(described_class.for(account)).to eq(setting)
    end
  end

  describe 'defaults' do
    it 'are valid' do
      expect(setting).to be_valid
    end

    it 'ship every feature disabled' do
      %w[window_keeper post_sale agent_panel email_marketing].each do |feature|
        expect(setting.feature_enabled?(feature)).to be(false)
      end
    end

    it 'are not mutated through the returned config' do
      setting.config['window_keeper']['skip_labels'] << 'otra'

      expect(described_class::DEFAULTS['window_keeper']['skip_labels']).not_to include('otra')
    end
  end

  describe '#merge_config' do
    it 'stores only the changed values and keeps the defaults for the rest' do
      setting.merge_config(window_keeper: { enabled: true })
      setting.save!

      expect(setting.reload[:config]).to eq('window_keeper' => { 'enabled' => true })
      expect(setting.section(:window_keeper)).to include('enabled' => true, 'nudge_after_hours' => 22)
    end

    it 'deep merges successive changes' do
      setting.merge_config(post_sale: { stages: { d7: { days: 8 } } })
      setting.merge_config(post_sale: { stages: { d7: { template: nil } } })

      expect(setting.section(:post_sale)['stages']['d7']).to eq(
        'days' => 8,
        'free_text' => described_class::DEFAULTS['post_sale']['stages']['d7']['free_text'],
        'template' => nil
      )
    end

    it 'replaces arrays instead of merging them' do
      setting.merge_config(window_keeper: { nudge_buttons: ['Dale'] })

      expect(setting.section(:window_keeper)['nudge_buttons']).to eq(['Dale'])
    end
  end

  describe 'validations' do
    {
      'more than three nudge buttons' => [{ window_keeper: { nudge_buttons: %w[a b c d] } }, 'window_keeper.nudge_buttons'],
      'a nudge button longer than 20 characters' => [{ window_keeper: { nudge_buttons: ['a' * 21] } }, 'window_keeper.nudge_buttons'],
      'pending conversations for nudges' => [{ window_keeper: { only_statuses: %w[open pending] } }, 'window_keeper.only_statuses'],
      'a nudge after the window closes' => [{ window_keeper: { nudge_after_hours: 24 } }, 'window_keeper.nudge_after_hours'],
      'an unknown timezone' => [{ timezone: 'Mars/Olympus' }, 'timezone'],
      'a string where a boolean is expected' => [{ post_sale: { enabled: 'true' } }, 'post_sale.enabled'],
      'a send hour outside 0-23' => [{ post_sale: { send_hour_local: 24 } }, 'post_sale.send_hour_local'],
      'a blank stage text' => [{ post_sale: { stages: { d1: { free_text: ' ' } } } }, 'post_sale.stages.d1.free_text'],
      'a daily email limit below the hourly one' => [{ email_marketing: { max_per_hour: 500, max_per_day: 400 } }, 'email_marketing.max_per_day']
    }.each do |description, (changes, field)|
      it "rejects #{description}" do
        setting.merge_config(changes)

        expect(setting).not_to be_valid
        expect(setting.errors.full_messages).to eq(["Invalid value for #{field}"])
      end
    end

    it 'accepts alert users that belong to the account' do
      administrator = create(:user, account: account, role: :administrator)
      setting.merge_config(post_sale: { alert_user_ids: [administrator.id] })

      expect(setting).to be_valid
    end

    it 'rejects alert users from another account' do
      setting.merge_config(post_sale: { alert_user_ids: [create(:user).id] })

      expect(setting).not_to be_valid
      expect(setting.errors.full_messages).to eq(['Invalid value for post_sale.alert_user_ids'])
    end

    it 'requires an alert recipient before enabling post-sale' do
      setting.merge_config(post_sale: { enabled: true })

      expect(setting).not_to be_valid
      expect(setting.errors.full_messages).to eq(['Invalid value for post_sale.alert_user_ids'])
    end

    it 'requires inbox access for an agent recipient but permits account administrators' do
      channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      agent = create(:user, account: account, role: :agent)
      setting.merge_config(post_sale: { enabled: true, alert_user_ids: [agent.id] })
      expect(setting).not_to be_valid

      create(:inbox_member, inbox: channel.inbox, user: agent)
      expect(setting).to be_valid

      administrator = create(:user, account: account, role: :administrator)
      setting.merge_config(post_sale: { alert_user_ids: [administrator.id] })
      expect(setting).to be_valid
    end
  end
end
