class HomeController < ApplicationController
  def show
    render plain: "home"
  end
end
