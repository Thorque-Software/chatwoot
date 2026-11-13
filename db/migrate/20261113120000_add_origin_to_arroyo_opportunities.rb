class AddOriginToArroyoOpportunities < ActiveRecord::Migration[7.1]
  def change
    # Anuncio de Meta que trajo la consulta (vacío = demanda orgánica). Ver Arroyo::Commercial::Origin.
    add_column :arroyo_opportunities, :origin, :jsonb, null: false, default: {}
  end
end
