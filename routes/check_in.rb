require 'models/check_ins'
require 'models/studio_space.rb'

get '/check_in/?' do

    studios = StudioSpace.where(:service_space_id => SS_ID).pluck(:name)

    reasons = ['Training', 'Personal Project', 'Business Project', 'Class Project']

    erb :check_in, :layout => :fixed_61_bare, :locals => {
       :studios => studios,
       :reasons => reasons,
    } 
end

post '/check_in/?' do

    checkIn = CheckIn.new

    checkIn.user_id = @user.id
    checkIn.username = @user.username
    checkIn.name = @user.full_name
    checkIn.university_status = @user.university_status
    checkIn.datetime = Time.current

    if !@user.expiration_date.nil? && @user.expiration_date > Date.today
        checkIn.expired = "No"
    else
        checkIn.expired = "Yes"
    end

    checkIn.visit_reason = params[:ReasonOfVisit]
    checkIn.studio_used = params[:StudioUsed]

    checkIn.save
    
    session.clear
    flash(:success, 'Checked In', 'You have been sucessfully checked in.')
    redirect '/check_in_login'
end