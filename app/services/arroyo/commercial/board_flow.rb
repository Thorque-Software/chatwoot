# Embudo de izquierda a derecha: origen (campaña, anuncio u orgánica) → a quién le toca (vendedor, bot o sin
# asignar) → en qué quedó. Devuelve nodos y enlaces con su cantidad; lo dibuja FunnelBoard.vue.
# Los orígenes más chicos se agrupan en "other" para que el gráfico se pueda leer.
class Arroyo::Commercial::BoardFlow
  TOP_ORIGINS = 6
  OTHER = 'other'.freeze

  def initialize(rows:, origins:, level:, seller_names:)
    @rows = rows
    @origins = origins
    @level = level
    @seller_names = seller_names
  end

  def build
    { nodes: origin_nodes + bucket_nodes + stage_nodes, links: origin_links + stage_links }
  end

  # Clave del nodo de origen de una consulta (las que no están entre las principales van a "other").
  def origin_of(row)
    key = @origins.key(row.record, @level)
    top_keys.include?(key) ? key : OTHER
  end

  private

  def top_keys
    @top_keys ||= begin
      counts = @rows.group_by { |row| @origins.key(row.record, @level) }.transform_values(&:size)
      ordered = counts.sort_by { |key, count| [-count, key] }.map(&:first)
      ordered.size > TOP_ORIGINS + 1 ? ordered.first(TOP_ORIGINS) : ordered
    end
  end

  def origin_nodes
    nodes = @rows.group_by { |row| origin_of(row) }.map do |key, items|
      label = key == OTHER ? nil : @origins.label(key)
      { id: "origin:#{key}", column: 0, kind: 'origin', key: key, label: label, value: items.size }
    end
    nodes.sort_by { |node| [node[:key] == OTHER ? 1 : 0, -node[:value]] }
  end

  def bucket_nodes
    nodes = @rows.group_by(&:bucket).map do |bucket, items|
      kind = %w[bot unassigned].include?(bucket) ? bucket : 'seller'
      { id: "bucket:#{bucket}", column: 1, kind: kind, key: bucket, label: @seller_names[bucket], value: items.size }
    end
    nodes.sort_by { |node| [node[:kind] == 'seller' ? 0 : 1, -node[:value]] }
  end

  def stage_nodes
    counts = @rows.select(&:seller?).group_by(&:stage).transform_values(&:size)
    Arroyo::Commercial::BoardRow::STAGES.filter_map do |stage|
      { id: "stage:#{stage}", column: 2, kind: 'stage', key: stage, label: nil, value: counts[stage] } if counts[stage]
    end
  end

  def origin_links
    links(@rows) { |row| ["origin:#{origin_of(row)}", "bucket:#{row.bucket}"] }
  end

  def stage_links
    links(@rows.select(&:seller?)) { |row| ["bucket:#{row.bucket}", "stage:#{row.stage}"] }
  end

  def links(rows, &)
    rows.group_by(&).map { |(source, target), items| { source: source, target: target, value: items.size } }
  end
end
