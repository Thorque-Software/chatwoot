namespace :arroyo do
  namespace :commercial do
    desc 'Reconstruye hechos comerciales comprobables sin envíos ni asignaciones (ACCOUNT_ID)'
    task backfill: :environment do
      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      Arroyo::Commercial::BackfillService.new(account: account).perform
      puts "Cobertura parcial reconstruida: cuenta #{account.id}"
    end
  end
end
