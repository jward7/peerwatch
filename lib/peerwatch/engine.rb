require "rails/engine"

module Peerwatch
  class Engine < ::Rails::Engine
    isolate_namespace Peerwatch

    # lib/tasks/*.rake is loaded by Rails::Engine itself; loading it again
    # here would define every task action twice.
  end
end
