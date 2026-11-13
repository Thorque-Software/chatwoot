# Sección funnel_board de Arroyo::Setting: el embudo unificado del panel de vendedores
# (abandonadas, etiquetas, números de WhatsApp y aviso antes de que cierre la ventana).
# Ver docs/arroyo/FUNNEL_BOARD.md.
module Arroyo::FunnelBoardConfig
  MAX_LABELS = 20
  MAX_INBOX_NAME_LENGTH = 60
  MAX_NUDGE_LENGTH = 1000
  CLOCK_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  DEFAULTS = {
    'enabled' => false,
    'abandon_hours' => 24,
    'lost_label' => 'noquierenada',
    'repurchase_label' => 'recompra',
    'info_labels' => [{ 'label' => 'cotizado', 'enabled' => true }, { 'label' => 'cuota', 'enabled' => true },
                      { 'label' => 'turnotaller', 'enabled' => true }],
    # Números de WhatsApp que muestra el embudo y su nombre. Vacío = todas las bandejas de la cuenta.
    'inboxes' => [],
    'window_nudge' => {
      'enabled' => false,
      'text' => 'Hola {{contact.first_name}}, ¿pudiste ver lo que te pasamos? Si querés seguimos por acá 😊',
      'morning_time' => '08:30',
      'evening_time' => '19:00',
      'skip_sundays' => true,
      'margin_minutes' => 30,
      'skip_labels' => ['seguimiento']
    }
  }.freeze

  VALID_LABEL = lambda { |item|
    item.is_a?(Hash) && item['label'].is_a?(String) && item['label'].strip.present? && [true, false].include?(item['enabled'])
  }

  VALID_INBOX = lambda { |item|
    item.is_a?(Hash) && item['id'].is_a?(Integer) && item['name'].is_a?(String) && item['name'].strip.length.between?(1, MAX_INBOX_NAME_LENGTH)
  }

  VALIDATORS = {
    clock: ->(value) { value.is_a?(String) && value.match?(CLOCK_FORMAT) },
    long_text: ->(value, max) { value.is_a?(String) && value.strip.present? && value.length <= max },
    board_labels: ->(value) { value.is_a?(Array) && value.size <= MAX_LABELS && value.all?(&VALID_LABEL) },
    board_inboxes: ->(value) { value.is_a?(Array) && value.all?(&VALID_INBOX) && value.pluck('id').uniq.size == value.size }
  }.freeze

  RULES = {
    'funnel_board.enabled' => [:boolean],
    'funnel_board.abandon_hours' => [:integer, 1, 720],
    'funnel_board.lost_label' => [:text],
    'funnel_board.repurchase_label' => [:text],
    'funnel_board.info_labels' => [:board_labels],
    'funnel_board.inboxes' => [:board_inboxes],
    'funnel_board.window_nudge.enabled' => [:boolean],
    'funnel_board.window_nudge.text' => [:long_text, MAX_NUDGE_LENGTH],
    'funnel_board.window_nudge.morning_time' => [:clock],
    'funnel_board.window_nudge.evening_time' => [:clock],
    'funnel_board.window_nudge.skip_sundays' => [:boolean],
    'funnel_board.window_nudge.margin_minutes' => [:integer, 0, 240],
    'funnel_board.window_nudge.skip_labels' => [:text_list]
  }.freeze

  private

  # El embudo lee las oportunidades del CRM: necesita el embudo comercial prendido.
  def validate_funnel_board(current)
    board = current['funnel_board']
    add_invalid_field('funnel_board.enabled') if board['enabled'] == true && current['agent_panel']['funnel_enabled'] != true
    validate_board_inboxes(board['inboxes'])
    nudge = board['window_nudge']
    return unless VALIDATORS[:clock].call(nudge['morning_time']) && VALIDATORS[:clock].call(nudge['evening_time'])

    add_invalid_field('funnel_board.window_nudge.evening_time') unless nudge['morning_time'] < nudge['evening_time']
  end

  def validate_board_inboxes(inboxes)
    return unless account && VALIDATORS[:board_inboxes].call(inboxes)

    add_invalid_field('funnel_board.inboxes') if (inboxes.pluck('id') - account.inboxes.pluck(:id)).any?
  end
end
