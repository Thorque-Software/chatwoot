# Rutas del fork Arroyo. Se cargan con `draw :arroyo` dentro del scope de cuenta
# en config/routes.rb: /api/v1/accounts/:account_id/arroyo/...
namespace :arroyo do
  resource :settings, only: [:show, :update]
  resource :features, only: [:show]
  resource :agent_panel, only: [:show], controller: 'agent_panel' do
    get :conversations
    get :windows
    get :export
  end
end
