class ApplicationController < ActionController::Base
  # Stands in for a host's authentication: a before_action that redirects
  # with one of the HOST's route helpers.
  before_action :bounce_locked_requests

  private

  def bounce_locked_requests
    redirect_to host_home_path if params[:locked]
  end
end
