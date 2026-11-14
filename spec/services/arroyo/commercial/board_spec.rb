require 'rails_helper'

RSpec.describe Arroyo::Commercial::Board do
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }
  let(:account) { create(:account) }
  # Sin display_name, como en prod: el panel muestra available_name.
  let(:juli) { create(:user, account: account, role: :agent, name: 'Julieta', display_name: nil, email: 'juli@example.com') }
  let(:marcos) { create(:user, account: account, role: :agent, name: 'Marcos', display_name: nil, email: 'marcos@example.com') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { zone.parse('2026-11-12 18:00') }
  let(:params) { { since: '2026-11-10', until: '2026-11-12' } }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [juli.id, marcos.id] },
                         funnel_board: { enabled: true })
    setting.save!
  end

  def inquiry(assignee: nil, at: '2026-11-11 10:00', labels: [], **attributes)
    conversation = create(:conversation, account: account, inbox: inbox, assignee: assignee)
    conversation.update!(label_list: labels) if labels.any?
    create(:arroyo_opportunity, conversation: conversation, assignee: assignee, started_at: zone.parse(at), **attributes)
  end

  def board(user: admin, extra: {})
    described_class.new(account_user: account.account_users.find_by(user: user), params: ActionController::Parameters.new(params.merge(extra)),
                        now: now)
  end

  def ad(id, campaign)
    { 'ad_id' => id, 'ad_name' => "Anuncio #{id}", 'ad_campaign_id' => campaign, 'ad_campaign_name' => "Campaña #{campaign}" }
  end

  it 'follows each inquiry from its origin to the current seller and its result' do
    inquiry(assignee: juli, state: 'won', first_human_at: now - 1.day, origin: ad('1', 'c1'))
    inquiry(assignee: juli, state: 'in_progress', first_human_at: now - 1.day, origin: ad('2', 'c1'))
    inquiry(assignee: marcos, state: 'pending')
    inquiry(state: 'bot')
    inquiry(assignee: marcos, state: 'lost', first_human_at: now - 1.day, at: '2026-11-09 10:00')

    data = board.build
    expect(data[:totals]).to include('received' => 4, 'attended' => 2, 'won' => 1, 'pending' => 1, 'bot' => 1,
                                     'assigned' => 3, 'from_ads' => 2, 'organic' => 2)
    links = data[:flow][:links].to_h { |link| [[link[:source], link[:target]], link[:value]] }
    expect(links[['origin:campaign:c1', "bucket:#{juli.id}"]]).to eq(2)
    expect(links[['origin:organic', 'bucket:bot']]).to eq(1)
    expect(links[["bucket:#{juli.id}", 'stage:won']]).to eq(1)
    expect(links[["bucket:#{marcos.id}", 'stage:pending']]).to eq(1)
    expect(data[:origins].first).to include(key: 'campaign:c1', name: 'Campaña c1', received: 2, won: 1)
    expect(data[:origins].first[:ads].pluck(:name)).to contain_exactly('Anuncio 1', 'Anuncio 2')
  end

  it 'credits a reassigned inquiry entirely to the current seller' do
    inquiry(assignee: marcos, first_assignee: juli, state: 'won', first_human_at: now - 1.day)

    sellers = board.build[:sellers].index_by { |seller| seller['name'] }
    expect(sellers['Marcos']).to include('received' => 1, 'attended' => 1, 'won' => 1)
    expect(sellers['Julieta']).to include('received' => 0)
  end

  it 'shows abandoned inquiries after the reminder and the configured hours' do
    record = inquiry(assignee: juli, state: 'in_progress', first_human_at: now - 3.days)
    record.events.create!(kind: 'window_nudge', source_key: 'nudge', origin: 'automation', occurred_at: now - 25.hours)

    expect(board.build[:totals]).to include('abandoned' => 1, 'in_progress' => 0, 'nudged' => 1)
  end

  it 'counts per day and seller, and the enabled informative labels' do
    inquiry(assignee: juli, at: '2026-11-10 09:00', labels: ['cotizado'])
    inquiry(assignee: juli, at: '2026-11-12 09:00', labels: %w[cuota cotizado])
    setting = Arroyo::Setting.for(account)
    setting.merge_config(funnel_board: { info_labels: [{ label: 'cotizado', enabled: true }, { label: 'cuota', enabled: false }] })
    setting.save!

    data = board.build
    expect(data[:days].pluck(:date)).to eq(%w[2026-11-10 2026-11-11 2026-11-12])
    expect(data[:days].map { |day| day[:sellers][juli.id.to_s]['received'] }).to eq([1, 0, 1])
    expect(data[:info_labels]).to eq([{ label: 'cotizado', count: 2 }])
  end

  it 'filters by the WhatsApp numbers of the configuration and rejects others' do
    other = create(:inbox, account: account)
    inquiry(assignee: juli)
    create(:arroyo_opportunity, conversation: create(:conversation, account: account, inbox: other), started_at: zone.parse('2026-11-11 10:00'))
    setting = Arroyo::Setting.for(account)
    setting.merge_config(funnel_board: { inboxes: [{ id: inbox.id, name: 'Arroyo' }] })
    setting.save!

    expect(board.build).to include(inboxes: [{ 'id' => inbox.id, 'name' => 'Arroyo' }])
    expect(board.build[:totals]['received']).to eq(1)
    expect(board(extra: { inbox_ids: [other.id.to_s] })).not_to be_valid
  end

  it 'lists post-sale messages that did not go out' do
    conversation = create(:conversation, account: account, inbox: inbox)
    purchase = Arroyo::PostSalePurchase.create!(account: account, conversation: conversation, contact: conversation.contact, inbox: inbox,
                                                seller: juli, reference: SecureRandom.uuid, purchased_at: now - 2.days,
                                                recorded_at: now - 2.days, product: 'Bici R29', rubro: 'bike')
    Arroyo::FollowUp.create!(account: account, purchase: purchase, stage: 'd1', status: 'failed', scheduled_at: now - 1.day,
                             error_message: 'Plantilla pausada')

    issues = board.build[:post_sale_issues]
    expect(issues[:count]).to eq(1)
    expect(issues[:items].first).to include(stage: 'd1', status: 'failed', error: 'Plantilla pausada', seller: 'Julieta')
  end

  it 'shows everyone the totals but only the own inquiries in the detail' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { agents_see_only_own: true })
    setting.save!
    create(:inbox_member, inbox: inbox, user: marcos)
    own = inquiry(assignee: marcos)
    inquiry(assignee: juli)

    view = board(user: marcos)
    expect(view.build[:totals]['received']).to eq(2)
    expect(view.select({}).map(&:record)).to eq([own])
    expect(view.select('bucket' => juli.id.to_s)).to be_empty
    expect(board.select('bucket' => 'waiting')).to be_empty
  end
end
