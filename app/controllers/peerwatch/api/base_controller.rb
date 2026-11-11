require "digest"

module Peerwatch
  module Api
    # Token-protected JSON for the other apps in the mesh. A missing, wrong or
    # unconfigured token gets an empty 404, so the endpoints reveal nothing.
    class BaseController < ActionController::API
      before_action :require_token

      private

      def require_token
        head :not_found unless Peerwatch.config.api_enabled? && token_matches?
      end

      def token_matches?
        presented = request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
        # Comparing digests keeps the lengths equal, so this cannot raise
        # and leaks nothing about the token's length.
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(presented), Digest::SHA256.hexdigest(Peerwatch.config.token.to_s)
        )
      end
    end
  end
end
