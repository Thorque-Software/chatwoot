# Recompra: cuando se gana una consulta de un cliente que ya había comprado antes (otra consulta ganada o una compra
# de postventa), la conversación recibe la etiqueta de recompra del embudo del panel. No toca la venta anterior.
class Arroyo::Commercial::RepurchaseLabelService
  def initialize(opportunity:)
    @opportunity = opportunity
  end

  def perform
    board = Arroyo::Setting.for(opportunity.account).section(:funnel_board)
    return unless board['enabled'] && opportunity.state == 'won' && earlier_sale?

    label = board['repurchase_label']
    conversation = opportunity.conversation.reload
    return if conversation.label_list.include?(label)

    opportunity.account.labels.find_or_create_by!(title: label)
    conversation.update!(label_list: conversation.label_list | [label])
  end

  private

  attr_reader :opportunity

  def earlier_sale?
    at = opportunity.outcome_at || Time.current
    Arroyo::Opportunity.where(account: opportunity.account, contact_id: opportunity.contact_id, state: 'won')
                       .where.not(id: opportunity.id).exists?(['outcome_at < ?', at]) ||
      Arroyo::PostSalePurchase.where(account: opportunity.account, contact_id: opportunity.contact_id)
                              .where('opportunity_id IS NULL OR opportunity_id <> ?', opportunity.id).exists?(['purchased_at < ?', at])
  end
end
