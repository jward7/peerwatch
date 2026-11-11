Rails.application.routes.draw do
  get "home", to: "home#show", as: :host_home
  mount Peerwatch::Engine, at: "/peerwatch"
end
