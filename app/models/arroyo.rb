module Arroyo
  # Label que el window keeper (Fase 2) pone cuando la ventana de 24 hs cierra sin respuesta
  WINDOW_CLOSED_LABEL = 'ventana-cerrada'.freeze

  def self.table_name_prefix
    'arroyo_'
  end
end
