# Completa los datos que el embudo del panel necesita y que no existían antes de prenderlo:
#  - origen: el anuncio guardado en la conversación pasa a la consulta que abrió (las anteriores a ad_referral_at
#    no tienen hora, así que se le asigna a la primera consulta de la conversación);
#  - perdidas: las consultas abiertas cuya conversación recibió la etiqueta de perdida durante la consulta.
# Solo escribe en tablas arroyo_*, no manda mensajes ni cambia asignaciones. Se puede correr más de una vez.
class Arroyo::Commercial::BoardBackfillService
  pattr_initialize [:account!]

  def perform
    { origins: backfill_origins, lost: backfill_lost }
  end

  private

  def setting
    @setting ||= Arroyo::Setting.for(account)
  end

  def backfill_origins
    count = 0
    account.conversations.where("additional_attributes ->> 'ad_id' IS NOT NULL").find_each do |conversation|
      opportunity = origin_target(conversation)
      next if opportunity.nil? || opportunity.origin.present?

      opportunity.update!(origin: Arroyo::Commercial::Origin.snapshot(conversation.additional_attributes))
      count += 1
    end
    count
  end

  def origin_target(conversation)
    scope = Arroyo::Opportunity.where(account: account, conversation: conversation).order(:started_at, :id)
    referral_at = parse_time(conversation.additional_attributes['ad_referral_at'])
    return scope.first unless referral_at

    scope.where(started_at: ..(referral_at + Arroyo::Commercial::Origin::FRESH)).last
  end

  def backfill_lost
    label = setting.section(:funnel_board)['lost_label']
    sold = setting.section(:post_sale)['trigger_label']
    count = 0
    Arroyo::Opportunity.active.where(account: account).includes(:conversation).find_each do |opportunity|
      conversation = opportunity.conversation
      next if conversation.label_list.include?(sold)

      tagged_at = label_added_at(conversation, label)
      next unless tagged_at && tagged_at >= opportunity.started_at

      mark_lost(opportunity, tagged_at)
      count += 1
    end
    count
  end

  def label_added_at(conversation, label)
    ActsAsTaggableOn::Tagging.joins(:tag).where(taggable: conversation, context: 'labels', tags: { name: label }).maximum(:created_at)
  end

  def mark_lost(opportunity, at)
    opportunity.with_lock do
      owner = opportunity.assignee
      opportunity.update!(state: 'lost', result_user: owner, outcome_at: at)
      opportunity.events.find_or_create_by!(source_key: 'board_backfill_lost') do |event|
        event.assign_attributes(kind: 'lost', origin: 'backfill', occurred_at: at, actor: owner, data: {})
      end
    end
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
