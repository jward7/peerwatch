Rails.application.routes.draw do
  get "home", to: "home#show", as: :host_home
  # Same name as an engine route, as many hosts have.
  get "dashboard", to: "home#show", as: :dashboard
  mount Peerwatch::Engine, at: "/peerwatch"
end
