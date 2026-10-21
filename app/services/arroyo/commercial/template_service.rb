class Arroyo::Commercial::TemplateService < Arroyo::PostSale::TemplateService
  NAMES = %w[seg_dia_1 seg_dia_3 seg_dia_5].freeze
  def initialize(opportunity:, step:)
    @step = step
    labels = opportunity.conversation.label_list
    rubro = 'generic'
    rubro = 'bike' if labels.include?('bici')
    rubro = 'gym' if labels.include?('aparatosgim')
    product = opportunity.product.presence || I18n.t("arroyo.post_sale.products.#{rubro}", locale: opportunity.account.locale)
    purchase = Struct.new(:inbox, :seller, :product).new(opportunity.inbox, opportunity.assignee, product)
    super(purchase: purchase, stage: 'd1')
  end

  private

  def template
    @template ||= Array(purchase.inbox.channel.message_templates).find do |item|
      item['name'] == NAMES[@step - 1] && item['language'] == 'es_AR' && item['status'] == 'APPROVED'
    end
  end
end
