class Arroyo::PostSale::AlertService
  pattr_initialize [:follow_up!]

  def perform
    follow_up.purchase.with_lock do
      follow_up.with_lock do
        next if follow_up.alerted_at || follow_up.delivered? || follow_up.purchase.excluded?

        create_alert
      end
    end
    follow_up
  end

  private

  def create_alert
    users = recipients
    follow_up.update!(manual_status: 'pending', alerted_at: Time.current, alert_assignee_id: users.first&.id)
    message = Messages::MessageBuilder.new(nil, follow_up.conversation, note_params(users)).perform
    follow_up.update!(alert_message: message)
    follow_up.conversation.with_lock { follow_up.conversation.add_labels(['seguimiento-manual']) }
  end

  def recipients
    purchase = follow_up.purchase
    ids = Arroyo::Setting.for(purchase.account).section(:post_sale)['alert_user_ids']
    allowed = purchase.account.administrators.pluck(:id) + purchase.inbox.members.pluck(:id)
    users = purchase.account.users.where(id: ids & allowed).to_a
    users.sort_by { |user| user.id == purchase.seller_id ? 0 : 1 }
  end

  def note_params(users)
    mentions = users.map { |user| "[@#{user.name}](mention://user/#{user.id}/#{ERB::Util.url_encode(user.name)})" }.join(' ')
    { content: "#{mentions}\n#{alert_text}", message_type: 'outgoing', private: true,
      content_attributes: { arroyo_kind: 'post_sale_alert', arroyo_follow_up_id: follow_up.id } }
  end

  def alert_text
    purchase = follow_up.purchase
    I18n.t('arroyo.post_sale.alert_note', locale: purchase.account.locale,
                                          stage: follow_up.stage, product: purchase.product,
                                          reason: follow_up.error_message, code: follow_up.error_code.presence || '-',
                                          phone: purchase.contact.phone_number.presence || '-',
                                          seller: purchase.seller&.available_name.presence || '-')
  end
end
