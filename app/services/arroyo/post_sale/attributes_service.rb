class Arroyo::PostSale::AttributesService
  KEYS = %w[seguimiento_envios seguimiento_ultimo_envio seguimiento_ultimo_envio_ts].freeze
  pattr_initialize [:conversation!, :attributes!]

  def perform
    values = attributes.to_h.stringify_keys
    raise Arroyo::PostSale::Error, 'invalid_attributes' if (values.keys - KEYS).any?

    conversation.with_lock { conversation.update!(custom_attributes: conversation.custom_attributes.merge(values)) }
    conversation
  end
end
