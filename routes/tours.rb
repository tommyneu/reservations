require 'models/event'
require 'models/event_signup'
require 'classes/emailer'

get '/tours/?' do
	not_found if SS_ID != 1

	@breadcrumbs << {:text => 'Tours'}
	tour_id = EventType.find_by(:description => 'Tour', :service_space_id => SS_ID).id

    erb :tours, :layout => :fixed_61, :locals => {
    	:events => Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => tour_id).where('start_time >= ?', Time.now).all
    }
end

get '/tours/sign_up/:event_id/?' do
	not_found if SS_ID != 1

	@breadcrumbs << {:text => 'Tours', :href => '/tours/'} << {text: 'Sign Up'}

	# check if this is a tour signup
	tour_id = EventType.find_by(:description => 'Tour', :service_space_id => SS_ID).id
	event = Event.includes(:event_signups).find_by(:service_space_id => SS_ID, :id => params[:event_id])
	if event.nil? || event.event_type_id != tour_id
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/tours/'
	elsif event.start_time.in_time_zone < DateTime.now.in_time_zone
	  event.start_time.in_time_zone.inspect
	  flash(:danger, 'Event Signup Closed', 'This event has passed')
    redirect '/tours/'
	end

	erb :tour_signup, :layout => :fixed_61, :locals => {
		:event => event
	}
end

post '/tours/sign_up/:event_id/?' do
	not_found if SS_ID != 1

	# check if this is a new member signup orientation
	tour_id = EventType.find_by(:description => 'Tour', :service_space_id => SS_ID).id
	event = Event.includes(:event_signups).find_by(:service_space_id => SS_ID, :id => params[:event_id])
	if event.nil? || event.event_type_id != tour_id
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/tours/'
	elsif event.start_time.in_time_zone < DateTime.now.in_time_zone
    event.start_time.in_time_zone.inspect
    flash(:danger, 'Event Signup Closed', 'This event has passed')
    redirect '/tours/'
	end

	VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
	if 	!VALID_EMAIL_REGEX.match(params[:email])
		flash(:danger, "Invalid Email", "Your email address was invalid")
		session[:form_data] = params
		redirect back
	end

	EventSignup.create(
		:event_id => params[:event_id],
		:name => params[:name],
		:email => params[:email]
	)

	body = <<EMAIL
<p>Thank you, #{params[:name]} for signing up for #{event.title}. Don't forget that the event is</p>

<p><strong>#{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}</strong>.</p>

<p>Our main entrance is on the northwest side of the Innovation Commons building on 19th St. just off Transformation Drive. Our address is 2021 Transformation Drive, Suite 1500, Entrance B.</p>

<p>We'll see you there!</p>

<p>Nebraska Innovation Studio</p>
EMAIL

	Emailer.mail(params[:email], "Nebraska Innovation Studio - #{event.title}", body)

	# flash a message that this works
	flash(:success, "You're signed up!", "Thanks for signing up! Don't forget, the tour is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}.")
	redirect '/tours/'
end

