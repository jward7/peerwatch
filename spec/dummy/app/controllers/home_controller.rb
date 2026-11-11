class HomeController < ApplicationController
  def show
    render html: "home", layout: true
  end
end
