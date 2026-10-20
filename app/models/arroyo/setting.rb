# == Schema Information
#
# Table name: arroyo_settings
#
#  id         :bigint           not null, primary key
#  config     :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_arroyo_settings_on_account_id  (account_id) UNIQUE
#
class Arroyo::Setting < ApplicationRecord
  STAGES = %w[d1 d7 d30].freeze
  # pending queda afuera: el bot de n8n responde en conversaciones pending (ver docs/arroyo/ARCHITECTURE_NOTES.md §14)
  NUDGE_STATUSES = %w[open snoozed].freeze
  MAX_NUDGE_BUTTONS = 3
  # Límite de Meta para el título de un botón de respuesta
  MAX_NUDGE_BUTTON_LENGTH = 20

  DEFAULTS = {
    'timezone' => 'America/Argentina/Buenos_Aires',
    'window_keeper' => {
      'enabled' => false,
      'nudge_after_hours' => 22,
      'only_statuses' => ['open'],
      'only_assigned' => true,
      'nudge_text' => 'Hola {{contact.first_name}}, ¿pudiste ver lo que te pasamos? Si querés seguimos por acá 👇',
      'nudge_buttons' => ['Sí, sigamos', 'Ya lo resolví'],
      'skip_labels' => %w[no-contactar venta-perdida],
      'reengagement_template' => nil
    },
    'post_sale' => {
      'enabled' => false,
      'trigger_label' => 'vendido',
      'send_hour_local' => 10,
      'skip_sundays' => false,
      'stages' => {
        'd1' => {
          'days' => 1,
          'template' => 'postventa_d1'
        },
        'd7' => {
          'days' => 7,
          'template' => 'postventa_d7'
        },
        'd30' => {
          'days' => 30,
          'template' => 'postventa_d30'
        }
      },
      'delivery_timeout_hours' => 6,
      'alert_user_ids' => [],
      'alert_email' => false
    },
    'agent_panel' => { 'enabled' => false, 'agents_see_only_own' => true, 'hide_native_reports' => false },
    'email_marketing' => { 'enabled' => false, 'max_per_hour' => 100, 'max_per_day' => 400, 'footer_html' => '' }
  }.freeze

  VALIDATORS = {
    boolean: ->(value) { [true, false].include?(value) },
    string: ->(value) { value.is_a?(String) },
    text: ->(value) { value.is_a?(String) && value.strip.present? },
    optional_text: ->(value) { value.nil? || (value.is_a?(String) && value.strip.present?) },
    text_list: ->(value) { value.is_a?(Array) && value.all? { |item| item.is_a?(String) && item.strip.present? } },
    integer_list: ->(value) { value.is_a?(Array) && value.all?(Integer) },
    integer: ->(value, min, max) { value.is_a?(Integer) && value.between?(min, max) },
    number: ->(value, min, max) { value.is_a?(Numeric) && value.between?(min, max) },
    timezone: ->(value) { value.is_a?(String) && ActiveSupport::TimeZone[value].present? },
    nudge_statuses: ->(value) { value.is_a?(Array) && value.present? && (value - NUDGE_STATUSES).empty? },
    nudge_buttons: lambda { |value|
      value.is_a?(Array) && value.size.between?(1, MAX_NUDGE_BUTTONS) &&
        value.all? { |item| item.is_a?(String) && item.strip.length.between?(1, MAX_NUDGE_BUTTON_LENGTH) }
    }
  }.freeze

  STAGE_RULES = STAGES.each_with_object({}) do |stage, rules|
    rules["post_sale.stages.#{stage}.days"] = [:integer, 1, 365]
    rules["post_sale.stages.#{stage}.template"] = [:text]
  end

  RULES = {
    'timezone' => [:timezone],
    'window_keeper.enabled' => [:boolean],
    # El nudge se manda entre nudge_after_hours y 23 h 45 min desde el último entrante
    'window_keeper.nudge_after_hours' => [:number, 1, 23.5],
    'window_keeper.only_statuses' => [:nudge_statuses],
    'window_keeper.only_assigned' => [:boolean],
    'window_keeper.nudge_text' => [:text],
    'window_keeper.nudge_buttons' => [:nudge_buttons],
    'window_keeper.skip_labels' => [:text_list],
    'window_keeper.reengagement_template' => [:optional_text],
    'post_sale.enabled' => [:boolean],
    'post_sale.trigger_label' => [:text],
    'post_sale.send_hour_local' => [:integer, 0, 23],
    'post_sale.skip_sundays' => [:boolean],
    'post_sale.delivery_timeout_hours' => [:number, 1, 72],
    'post_sale.alert_user_ids' => [:integer_list],
    'post_sale.alert_email' => [:boolean],
    'agent_panel.enabled' => [:boolean],
    'agent_panel.agents_see_only_own' => [:boolean],
    'agent_panel.hide_native_reports' => [:boolean],
    'email_marketing.enabled' => [:boolean],
    'email_marketing.max_per_hour' => [:integer, 1, 10_000],
    'email_marketing.max_per_day' => [:integer, 1, 100_000],
    'email_marketing.footer_html' => [:string]
  }.merge(STAGE_RULES).freeze

  belongs_to :account

  validates :account_id, uniqueness: true
  validate :validate_config

  def self.for(account)
    find_or_initialize_by(account: account)
  end

  # Lo guardado en la columna son solo los valores que se cambiaron; el resto sale de DEFAULTS.
  def config
    result = DEFAULTS.deep_dup.deep_merge(self[:config])
    STAGES.each do |stage|
      result['post_sale']['stages'][stage].delete('free_text')
      result['post_sale']['stages'][stage]['template'] = DEFAULTS['post_sale']['stages'][stage]['template']
    end
    result
  end

  def merge_config(changes)
    self[:config] = self[:config].deep_merge(changes.to_h.deep_stringify_keys)
  end

  def section(name)
    config.fetch(name.to_s)
  end

  def feature_enabled?(name)
    section(name)['enabled']
  end

  private

  def validate_config
    current = config
    RULES.each do |path, (type, *args)|
      add_invalid_field(path) unless VALIDATORS.fetch(type).call(value_at(current, path), *args)
    end
    validate_email_limits(current['email_marketing'])
    validate_alert_users(current['post_sale']['alert_user_ids'])
    validate_post_sale_recipients(current['post_sale'])
  end

  def validate_email_limits(email_marketing)
    per_hour, per_day = email_marketing.values_at('max_per_hour', 'max_per_day')
    return unless per_hour.is_a?(Integer) && per_day.is_a?(Integer)

    add_invalid_field('email_marketing.max_per_day') if per_day < per_hour
  end

  def validate_alert_users(user_ids)
    return unless account && VALIDATORS[:integer_list].call(user_ids)

    add_invalid_field('post_sale.alert_user_ids') if (user_ids - account.account_users.pluck(:user_id)).any?
  end

  def validate_post_sale_recipients(post_sale)
    return unless account && post_sale['enabled'] == true

    ids = post_sale['alert_user_ids']
    return unless VALIDATORS[:integer_list].call(ids)

    invalid = ids.empty? || account.inboxes.where(channel_type: 'Channel::Whatsapp').any? do |inbox|
      (ids - (account.administrators.pluck(:id) + inbox.members.pluck(:id))).any?
    end
    add_invalid_field('post_sale.alert_user_ids') if invalid
  end

  def value_at(hash, path)
    path.split('.').reduce(hash) { |node, key| node.is_a?(Hash) ? node[key] : nil }
  end

  def add_invalid_field(path)
    errors.add(:base, :invalid_field, field: path)
  end
end
