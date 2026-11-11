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
    def self.use_host_routes(klass)
      klass.define_singleton_method(:_routes) { Rails.application.routes }
      klass.define_method(:_routes) { Rails.application.routes }
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
