# Rutas del fork Arroyo. Se cargan con `draw :arroyo` dentro del scope de cuenta
# en config/routes.rb: /api/v1/accounts/:account_id/arroyo/...
namespace :arroyo do
  scope :social_comments, controller: 'social_comments' do
    get 'channels', action: :channels
    post 'channels', action: :create_channel
    patch 'channels/:id', action: :update_channel
    get 'comments', action: :index
    get 'conversations/:conversation_id', action: :context
    get 'verify', action: :verify
    post 'ingest', action: :ingest
    post 'enrich', action: :enrich
    post 'claim', action: :claim
    post 'replies/:id/acknowledge', action: :acknowledge
    post 'replies/:id/retry', action: :retry
  end
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
