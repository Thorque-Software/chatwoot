namespace :arroyo do
  namespace :commercial do
    desc 'Previsualiza seguimientos ya etiquetados (ACCOUNT_ID, CONVERSATION_IDS); APPLY=1 confirma solo esos chats'
    task enroll_followups: :environment do
      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      ids = ENV.fetch('CONVERSATION_IDS').split(',').map { |value| Integer(value.strip) }
      apply = ENV['APPLY'] == '1'
      account.conversations.where(display_id: ids).find_each do |conversation|
        labelled_at = conversation.taggings.joins(:tag).where(tags: { name: 'seguimiento' }).minimum(:created_at)
        next puts({ conversation_id: conversation.display_id, status: 'without_label' }.to_json) unless labelled_at

        lifecycle = Arroyo::Commercial::Lifecycle.new(conversation: conversation)
        opportunity = lifecycle.current
        if apply && !opportunity&.events&.exists?(kind: 'follow_up_enrolled')
          lifecycle.labels(actor: nil, at: labelled_at, change: [[], ['seguimiento']])
          opportunity = lifecycle.current
        end
        existing = opportunity&.events&.exists?(kind: 'follow_up_enrolled')
        schedule = Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).as_json if existing
        zone = ActiveSupport::TimeZone[Arroyo::Setting.for(account).config['timezone']]
        date = labelled_at.in_time_zone(zone).to_date + 1
        date += 1 if date.sunday?
        first_at = zone.local(date.year, date.month, date.day, 10)
        puts({ conversation_id: conversation.display_id, mode: apply ? 'apply' : 'preview',
               labelled_at: labelled_at.iso8601, legacy_attributes: conversation.custom_attributes.slice('seguimiento_envios',
                                                                                                         'seguimiento_ultimo_envio'),
               first_follow_up_at: first_at.iso8601,
               enrolled: existing.present?, schedule: schedule }.to_json)
      end
    end
  end
end
