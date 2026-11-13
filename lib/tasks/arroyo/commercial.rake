namespace :arroyo do
  namespace :commercial do
    desc 'Reconstruye hechos comerciales comprobables sin envíos ni asignaciones (ACCOUNT_ID)'
    task backfill: :environment do
      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      Arroyo::Commercial::BackfillService.new(account: account).perform
      puts "Cobertura parcial reconstruida: cuenta #{account.id}"
    end

    desc 'Completa origen (anuncio u orgánica) y perdidas para el embudo del panel (ACCOUNT_ID)'
    task board_backfill: :environment do
      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      result = Arroyo::Commercial::BoardBackfillService.new(account: account).perform
      puts "Embudo del panel: #{result[:origins]} consultas con anuncio, #{result[:lost]} marcadas como perdidas (cuenta #{account.id})"
    end
  end
end
