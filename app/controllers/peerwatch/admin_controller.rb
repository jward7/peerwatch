module Peerwatch
  # The admin pages inherit the host's controller, so they get its
  # authentication, authorisation and layout.
  class AdminController < Peerwatch.config.admin_parent_controller.constantize
    # An isolated engine's controllers resolve every route helper against the
    # ENGINE's routes, which breaks the host code these pages inherit: its
    # sign-in redirect, its layout, its navbar. Put the host's routes back in
    # charge and reach the engine's own routes through the `peerwatch.`
    # mounted helper instead.
    #
    # Rails includes the engine's route helpers into every controller in the
    # namespace as it is defined, so this is defined on each class directly:
    # a shared module would sit behind that include and lose.
    #
    # The engine's named helpers (dashboard_path, ...) come from that include
    # too, and would shadow a host helper of the same name: a host
    # before_action calling `dashboard_path` would get the engine's route,
    # without its mount prefix. Prepending the host's named-route modules puts
    # them first. They are the live modules Rails fills when routes are
    # drawn or reloaded, so this holds with lazily loaded routes too.
    def self.use_host_routes(klass)
      routes = Rails.application.routes
      klass.define_singleton_method(:_routes) { Rails.application.routes }
      klass.define_method(:_routes) { Rails.application.routes }
      klass.prepend(routes.named_routes.path_helpers_module, routes.named_routes.url_helpers_module)
    end

    def self.inherited(klass)
      super
      use_host_routes(klass)
    end

    use_host_routes(self)

    layout -> { Peerwatch.config.layout }
    helper Peerwatch::DashboardHelper
  end
end
