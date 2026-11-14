require 'csv'

# Embudo unificado del panel (funnel_board). Lo ve cualquier usuario de la cuenta con los números de todos;
# el detalle de las consultas respeta los permisos de cada uno.
class Api::V1::Accounts::Arroyo::BoardController < Api::V1::Accounts::BaseController
  PAGE_SIZE = 50
  FILTERS = %w[origin bucket stage label attended metric date].freeze

  before_action :require_board
  before_action :load_board

  def show
    render json: @board.build
  end

  def opportunities
    rows = @board.select(params.permit(*FILTERS).to_h).sort_by { |row| [-row.record.started_at.to_f, -row.record.id] }
    render json: { opportunities: opportunities_json(rows.slice(offset, PAGE_SIZE) || []),
                   meta: { total: rows.size, next_page: offset + PAGE_SIZE < rows.size ? page + 1 : nil } }
  end

  def export
    data = @board.build
    csv = CSV.generate do |rows|
      rows << [I18n.t('arroyo.board.csv.date'), I18n.t('arroyo.board.csv.seller'), *counter_headers]
      data[:days].each { |day| export_day(rows, day, data[:sellers]) }
    end
    send_data csv, type: 'text/csv', filename: "arroyo_embudo_#{params[:since]}_#{params[:until]}.csv"
  end

  private

  def require_board
    setting = ::Arroyo::Setting.for(Current.account)
    return if setting.section(:funnel_board)['enabled'] && setting.section(:agent_panel)['funnel_enabled'] && setting.feature_enabled?(:agent_panel)

    render json: { errors: ['disabled'], code: 'disabled' }, status: :forbidden
  end

  def load_board
    @board = ::Arroyo::Commercial::Board.new(account_user: Current.account_user, params: params)
    render json: { errors: @board.errors }, status: :unprocessable_entity unless @board.valid?
  end

  def opportunities_json(rows)
    items = ::Arroyo::Commercial::Presenter.new(rows.map(&:record)).as_json
    items.zip(rows).map { |item, row| item.merge(stage: row.stage) }
  end

  def counter_headers
    ::Arroyo::Commercial::BoardRow::COUNTERS.map { |counter| I18n.t("arroyo.board.counters.#{counter}") }
  end

  def export_day(rows, day, sellers)
    rows << [day[:date], I18n.t('arroyo.board.csv.total'), *day[:total].values]
    sellers.each { |seller| rows << [day[:date], seller['name'], *day[:sellers][seller['id'].to_s].values] }
  end

  def page
    [params[:page].to_i, 1].max
  end

  def offset
    (page - 1) * PAGE_SIZE
  end
end
