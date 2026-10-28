require "erb"
require "json"
require "net/http"
require "models/user"

get "/engineering_design_hub/user_agreement/?" do
  require_login("engineering_design_hub/user_agreement")
  @breadcrumbs << { :text => "User Agreement Renewal" }

  erb :'/engineering_design_hub/user_agreement', :layout => :fixed_61
end

get "/engineering_design_hub/user_agreement_view_only/?" do
  require_login
  @breadcrumbs << { :text => "User Agreement Renewal View Only" }

  erb :'/engineering_design_hub/user_agreement_view_only', :layout => :fixed_61
end

post "/engineering_design_hub/user_agreement/?" do
  #On form submit, update user agreement expiration date
  @user.set_user_agreement_expiration_date(Date.today.next_year)
  redirect "/home/"
end
