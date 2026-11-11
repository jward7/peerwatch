Peerwatch::Engine.routes.draw do
  get  "status",   to: "api/status#show"
  get  "registry", to: "api/registry#index"
  post "registry", to: "api/registry#create"
  get  "/", to: "dashboard#show", as: :dashboard
  resources :peers, except: :show, as: :mesh_peers
end
