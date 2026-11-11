module Peerwatch
  module Api
    class RegistryController < BaseController
      # Every row, tombstones included, so removals sync too.
      def index
        render json: { peers: Peer.order(:name).map(&:registry_row) }
      end

      def create
        render json: { applied: RegistryMerge.call(incoming_rows) }
      end

      private

      # Rows are validated by the model during the merge; only the registry
      # fields are read from each one.
      def incoming_rows
        Array(params[:peers]).filter_map do |row|
          next unless row.respond_to?(:permit)

          row.permit(*(Peer::REGISTRY_FIELDS - [ "contact_emails" ]), contact_emails: []).to_h
        end
      end
    end
  end
end
