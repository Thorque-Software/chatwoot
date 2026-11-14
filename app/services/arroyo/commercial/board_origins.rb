# Origen de las consultas para el embudo: campaña o anuncio de Meta, u orgánica.
# Los nombres de campaña/anuncio pueden faltar en la consulta (Meta los resuelve después): se completan con los de
# cualquier conversación de la cuenta que tenga el mismo anuncio.
class Arroyo::Commercial::BoardOrigins
  LEVELS = %w[campaign ad].freeze
  ORGANIC = 'organic'.freeze

  def initialize(account:, records:)
    @account = account
    @records = records
  end

  def info(record)
    origin = record.origin || {}
    return {} if Arroyo::Commercial::Origin.organic?(origin)

    (names[origin['ad_id']] || {}).merge(origin.compact_blank)
  end

  def key(record, level)
    data = info(record)
    return ORGANIC if data.empty?
    return "campaign:#{data['ad_campaign_id']}" if level == 'campaign' && data['ad_campaign_id'].present?

    "ad:#{data['ad_id']}"
  end

  def label(key)
    labels[key] || key
  end

  # Tabla de campañas con sus anuncios: consultas, atendidas, ganadas y perdidas. La orgánica va al final.
  def table(rows)
    groups = rows.group_by { |row| key(row.record, 'campaign') }
    campaigns = groups.except(ORGANIC).map { |campaign_key, items| campaign_row(campaign_key, items) }
    campaigns.sort_by! { |item| [-item[:won], -item[:received]] }
    groups[ORGANIC] ? campaigns + [summary(ORGANIC, groups[ORGANIC]).merge(kind: 'organic', ads: [])] : campaigns
  end

  private

  def campaign_row(campaign_key, items)
    ads = items.group_by { |row| key(row.record, 'ad') }.map { |ad_key, ad_rows| summary(ad_key, ad_rows) }
    summary(campaign_key, items).merge(kind: 'campaign', ads: ads.sort_by { |item| [-item[:won], -item[:received]] })
  end

  def summary(key, rows)
    counts = Arroyo::Commercial::BoardRow.counts(rows)
    { key: key, name: label(key), received: counts['received'], attended: counts['attended'], won: counts['won'], lost: counts['lost'] }
  end

  def labels
    @labels ||= @records.map { |record| info(record) }.reject(&:empty?).each_with_object({}) do |data, result|
      result["ad:#{data['ad_id']}"] = first_present(data, 'ad_name', 'ad_headline', 'ad_id')
      result["campaign:#{data['ad_campaign_id']}"] = first_present(data, 'ad_campaign_name', 'ad_campaign_id') if data['ad_campaign_id']
    end
  end

  def first_present(data, *keys)
    data.values_at(*keys).find(&:present?)
  end

  def names
    @names ||= begin
      missing = @records.filter_map { |record| record.origin&.dig('ad_id') if record.origin&.dig('ad_campaign_id').blank? }.uniq
      missing.empty? ? {} : lookup(missing)
    end
  end

  def lookup(ad_ids)
    rows = @account.conversations.where("additional_attributes ->> 'ad_id' IN (?)", ad_ids)
                   .where("additional_attributes ->> 'ad_campaign_id' IS NOT NULL").pluck(:additional_attributes)
    rows.each_with_object({}) do |attributes, result|
      result[attributes['ad_id']] ||= attributes.slice(*Arroyo::Commercial::Origin::NAME_FIELDS).compact_blank
    end
  end
end
