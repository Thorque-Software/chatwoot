# Run only against local development: bundle exec rails runner script/arroyo/commercial_demo.rb
raise 'Development only' unless Rails.env.development?

ActiveJob::Base.queue_adapter = :test
account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
sellers = account.users.where(id: [4, 5]).order(:id).to_a
raise 'Two local sellers are required' unless sellers.size == 2

setting = Arroyo::Setting.for(account)
setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, balanced_assignment_enabled: true,
                                    agents_see_only_own: true, seller_ids: sellers.map(&:id) })
setting.save!
inbox = account.inboxes.find_by(name: 'DEMO LOCAL · Embudo comercial')
inbox ||= Inbox.create!(account: account, channel: Channel::Api.create!(account: account), name: 'DEMO LOCAL · Embudo comercial',
                        enable_auto_assignment: false)
sellers.each { |seller| InboxMember.find_or_create_by!(inbox: inbox, user: seller) }
zone = ActiveSupport::TimeZone[setting.config['timezone']]
today = Time.current.in_time_zone(zone).to_date
names = ['En el bot', 'Sin asignar', 'Pendiente Juli', 'En gestión Marcos', 'Ganada Juli', 'Perdida Marcos',
         'Cliente sin respuesta', 'Traspaso Juli a Marcos', 'Recompra confirmada', 'Incidencia postventa']
# Keep the synthetic scenarios together so their sequence is easy to inspect.
# rubocop:disable Metrics/BlockLength
names.each_with_index do |name, index|
  identifier = "commercial-demo-#{index}@arroyo.test"
  next if account.contacts.exists?(email: identifier)

  contact = account.contacts.create!(name: "DEMO · #{name}", email: identifier)
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  seller = if index < 2
             nil
           else
             sellers[index.even? ? 0 : 1]
           end
  conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                      assignee: seller, status: index.zero? ? :pending : :open)
  started = (today - (index >= 6 ? 6 : index % 4)).in_time_zone(zone).change(hour: 9)
  conversation.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: contact,
                                content: 'Hola, quisiera consultar por una bicicleta.', created_at: started)
  lifecycle = Arroyo::Commercial::Lifecycle.new(conversation: conversation)
  opportunity = lifecycle.current
  if index >= 3
    conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, sender: seller,
                                  content: 'Hola, te ayudo con tu consulta.', status: :delivered, created_at: started + 30.minutes)
  end
  lifecycle.outcome(opportunity.reload, outcome: 'won', user: seller, product: 'Bicicleta de demostración') if [4, 8, 9].include?(index)
  lifecycle.outcome(opportunity.reload, outcome: 'lost', user: seller) if index == 5
  if index == 6
    3.times do |step|
      conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, sender: nil, status: :delivered,
                                    content: 'Seguimiento automático de demostración.', created_at: started + (step * 2.days) + 1.hour,
                                    content_attributes: { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: opportunity.reference,
                                                          arroyo_step: step + 1 })
    end
  end
  conversation.update!(assignee: sellers.last) if index == 7
  next unless [8, 9].include?(index)

  purchase = Arroyo::PostSalePurchase.create!(account: account, conversation: conversation, contact: contact, inbox: inbox,
                                              seller: seller, opportunity: opportunity, purchased_at: started + 2.hours,
                                              recorded_at: started + 2.hours, product: 'Bicicleta de demostración')
  Arroyo::FollowUp::STAGES.each do |stage|
    purchase.follow_ups.create!(account: account, stage: stage, scheduled_at: started + 1.day,
                                status: index == 9 ? 'failed' : 'scheduled', error_code: index == 9 ? 'demo_only' : nil)
  end
  next unless index == 8

  repeat = lifecycle.start!(request_key: "demo-repeat-#{conversation.id}", user: seller, product: 'Accesorio de demostración')
  lifecycle.outcome(repeat, outcome: 'won', user: seller)
end
# rubocop:enable Metrics/BlockLength
Rails.logger.info({ account_id: account.id, demo_inbox_id: inbox.id, demo_opportunities: Arroyo::Opportunity.where(inbox: inbox).count }.to_json)
