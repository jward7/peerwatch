module Peerwatch
  module Api
    class StatusController < BaseController
      def show
        render json: StatusReport.build
      end
    end
  end
end
