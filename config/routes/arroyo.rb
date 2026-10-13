# Rutas del fork Arroyo. Se cargan con `draw :arroyo` dentro del scope de cuenta
# en config/routes.rb: /api/v1/accounts/:account_id/arroyo/...
namespace :arroyo do
  scope :post_sale, controller: 'post_sale' do
    get 'purchases', action: :purchases
    put 'purchases/:reference/plan', action: :plan
    patch 'purchases/:reference', action: :correct_date
    get 'follow_ups', action: :index
    post 'follow_ups/:id/message', action: :create_message
    post 'follow_ups/:id/resolve', action: :resolve
    post 'conversations/:conversation_id/attributes', action: :merge_attributes
  end
  resource :settings, only: [:show, :update]
  resource :features, only: [:show]
  resource :agent_panel, only: [:show], controller: 'agent_panel' do
    get :conversations
    get :windows
    get :export
  end
end
