class Arroyo::PostSale::Presenter
  pattr_initialize [:account_user!]

  def purchase(record)
    {
      reference: record.reference, revision: record.revision, planned_revision: record.planned_revision,
      purchased_at: record.purchased_at.iso8601, product: record.product, rubro: record.rubro,
      seller: { id: record.seller_id, name: record.seller&.available_name },
      conversation_id: record.conversation.display_id, can_reply: record.conversation.can_reply?,
      contact: contact(record), inbox: inbox(record),
      can_edit_purchase: purchase_policy(record).update?,
      follow_ups: record.follow_ups.sort_by { |item| Arroyo::FollowUp::STAGES.index(item.stage) }.map { |item| stage(item) }
    }
  end

  def follow_up(record)
    stage(record).merge(
      **delivery_details(record), **manual_details(record),
      can_resolve: record.manual_status == 'pending' && follow_up_policy(record).resolve?,
      purchase: purchase(record.purchase).except(:follow_ups, :inbox),
      message: message_details(record.message)
    )
  end

  private

  def delivery_details(record)
    { attempted_at: record.attempted_at&.iso8601, delivered_at: record.delivered_at&.iso8601, read_at: record.read_at&.iso8601,
      error_code: record.error_code, error_message: record.error_message, channel_used: record.channel_used, template_name: record.template_name }
  end

  def manual_details(record)
    { manual_status: record.manual_status, alert_assignee_id: record.alert_assignee_id, resolved_at: record.resolved_at&.iso8601,
      resolution_method: record.resolution_method, resolution_note: record.resolution_note }
  end

  def message_details(message)
    message&.slice(:id, :content, :status, :source_id)&.merge(template_params: message.additional_attributes['template_params'])
  end

  def stage(record)
    { id: record.id, stage: record.stage, status: record.status, scheduled_at: record.scheduled_at&.iso8601, message_id: record.message_id }
  end

  def contact(record)
    record.contact.slice(:id, :phone_number).merge(name: record.contact.name.to_s)
  end

  def inbox(record)
    channel = record.inbox.channel
    keys = %w[name language status category parameter_format components]
    templates = record.inbox.channel_type == 'Channel::Whatsapp' ? Array(channel.message_templates).map { |template| template.slice(*keys) } : []
    { id: record.inbox_id, channel_type: record.inbox.channel_type, message_templates: templates }
  end

  def context
    { user: account_user.user, account: account_user.account, account_user: account_user }
  end

  def purchase_policy(record)
    Arroyo::PostSalePurchasePolicy.new(context, record)
  end

  def follow_up_policy(record)
    Arroyo::FollowUpPolicy.new(context, record)
  end
end
