require 'rails_helper'

RSpec.describe Arroyo::Commercial::BoardBackfillService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  def conversation_with(attributes = {})
    create(:conversation, account: account, additional_attributes: attributes)
  end

  describe 'origins' do
    it 'gives the ad of an old conversation to its first inquiry only' do
      conversation = conversation_with('ad_id' => '52615', 'ad_name' => 'Reel Bici', 'ad_body' => 'Texto')
      first = create(:arroyo_opportunity, conversation: conversation, state: 'won', started_at: 10.days.ago)
      later = create(:arroyo_opportunity, conversation: conversation, started_at: 2.days.ago)

      expect(service.perform[:origins]).to eq(1)
      expect(first.reload.origin).to eq('ad_id' => '52615', 'ad_name' => 'Reel Bici')
      expect(later.reload.origin).to eq({})
    end

    it 'uses the arrival time of the ad when it is known' do
      conversation = conversation_with('ad_id' => '52615', 'ad_referral_at' => 2.days.ago.iso8601)
      first = create(:arroyo_opportunity, conversation: conversation, state: 'won', started_at: 10.days.ago)
      later = create(:arroyo_opportunity, conversation: conversation, started_at: 2.days.ago)

      service.perform
      expect(first.reload.origin).to eq({})
      expect(later.reload.origin).to eq('ad_id' => '52615')
    end

    it 'can run twice without changing anything' do
      conversation = conversation_with('ad_id' => '52615')
      create(:arroyo_opportunity, conversation: conversation)

      service.perform
      expect(service.perform[:origins]).to eq(0)
    end
  end

  describe 'lost inquiries' do
    let(:seller) { create(:user, account: account, role: :agent) }

    def opportunity_labelled(labels, at:)
      conversation = create(:conversation, account: account, assignee: seller)
      opportunity = create(:arroyo_opportunity, conversation: conversation, started_at: 3.days.ago)
      travel_to(at) { conversation.update!(label_list: labels) }
      opportunity
    end

    it 'marks lost the open inquiries labelled noquierenada during the inquiry' do
      labelled_at = 1.day.ago.change(usec: 0)
      opportunity = opportunity_labelled(['noquierenada'], at: labelled_at)

      expect(service.perform[:lost]).to eq(1)
      expect(opportunity.reload).to have_attributes(state: 'lost', result_user_id: seller.id)
      expect(opportunity.outcome_at).to be_within(1.second).of(labelled_at)
      expect(opportunity.events.pluck(:kind, :origin)).to include(%w[lost backfill])
    end

    it 'skips labels older than the inquiry and sold conversations' do
      old = opportunity_labelled(['noquierenada'], at: 5.days.ago)
      sold = opportunity_labelled(%w[noquierenada vendido], at: 1.day.ago)

      expect(service.perform[:lost]).to eq(0)
      expect([old.reload.state, sold.reload.state]).to eq(%w[in_progress in_progress])
    end
  end
end
