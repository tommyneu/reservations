require 'models/attended_orientation'
require 'models/user'
require 'models/event_signup'

before '/admin/orientation_attended*' do
	unless has_permission?(Permission::MANAGE_USERS) || has_permission?(Permission::SUPER_USER)
        raise Sinatra::NotFound
    end
end

get '/admin/orientation_attended/?' do 
    @breadcrumbs << {:text => 'View Orientation attendees'}

    attendees = AttendedOrientation.all.order_by_last_name

    erb :'admin/orientation_attended', :layout => :fixed_61, :locals => {
        :attendees => attendees,
    }

end

post '/admin/orientation_attended/?' do
    attendees = AttendedOrientation.all

    attendees.each do |attendee|
        if params.has_key?("expiration-date_#{attendee.user_id}") && params["expiration-date_#{attendee.user_id}"] != ""
            user = User.find_by(:id => attendee.user_id, :service_space_id => SS_ID)
            user.set_expiration_date(calculate_time(params[:"expiration-date_#{attendee.user_id}"], 0, 0, 'am'))

            status = "expired"
            if user.is_current?
                status = "current"
            end

            user.space_status = status
            user.save

            event_signup = EventSignup.find_by(:user_id => attendee.user_id, :event_id => attendee.event_id)
            if !event_signup.nil?
                event_signup.delete
            end

            orientation_attendee = AttendedOrientation.find_by(:user_id => attendee.user_id)
            if !orientation_attendee.nil?
                orientation_attendee.delete
            end

        end
    end

    attendees = AttendedOrientation.all.order_by_last_name

    erb :'admin/orientation_attended', :layout => :fixed_61, :locals => {
        :attendees => attendees,
    }

end