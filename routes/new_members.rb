require 'models/event'
require 'models/event_signup'
require 'models/emergency_contact'
require 'classes/emailer'
require 'recaptcha'

Recaptcha.configure do |config|
	config.site_key = CONFIG['reCaptcha']['site_key']
	config.secret_key = CONFIG['reCaptcha']['secret_key']
end

include Recaptcha::Adapters::ControllerMethods
include Recaptcha::Adapters::ViewMethods


get '/new_members/?' do
	@breadcrumbs << {:text => 'New Members'}
	new_member_orientation_id = EventType.find_by(:description => 'New Member Orientation', :service_space_id => SS_ID).id

    erb :new_members, :layout => :fixed, :locals => {
    	:events => Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => new_member_orientation_id, :is_private => 0).where('start_time >= ?', Time.now).order(:start_time => :asc).all
    }
end

get '/new_members/sign_up/:event_id/?' do
	@breadcrumbs << {:text => 'New Members', :href => '/new_members/'} << {text: 'Sign Up'}

	# check if this is a new member signup orientation
	new_member_orientation_id = EventType.find_by(:description => 'New Member Orientation', :service_space_id => SS_ID).id
	event = Event.includes(:event_signups).find_by(:service_space_id => SS_ID, :id => params[:event_id])
	if event.nil? || event.event_type_id != new_member_orientation_id
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/new_members/'
	end

	if !event.max_signups.nil? && event.signups.count >= event.max_signups
		# that event is full
		flash(:alert, 'This Orientation is Full', "Sorry, #{event.title} is full.")
		redirect '/new_members/'
	end

	erb :new_member_signup, :layout => :fixed, :locals => {
		:event => event,
		:recaptcha => Recaptcha.recaptcha_tags
	}
end

post '/new_members/sign_up/:event_id/?' do
	# check if this is a new member signup orientation
	new_member_orientation_id = EventType.find_by(:description => 'New Member Orientation', :service_space_id => SS_ID).id
	event = Event.includes(:event_signups).find_by(:service_space_id => SS_ID, :id => params[:event_id])
	if event.nil? || event.event_type_id != new_member_orientation_id
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/new_members/'
	end

	if !event.max_signups.nil? && event.signups.count >= event.max_signups
		# that event is full
		flash(:alert, 'This Orientation is Full', "Sorry, #{event.title} is full.")
		redirect '/new_members/'
	end

	if !verify_recaptcha
		flash(:alert, 'Google Recaptcha Verification Failed', 'Please try again.')
		redirect back
	end

	body = <<EMAIL
<p>Thank you, #{params[:name]} for signing up for #{event.title}. Don't forget that the event is</p>

<p><strong>#{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}</strong>.</p>

<p>Our main entrance is on the northwest side of the Innovation Commons building on 19th St. just off Transformation Drive. Our address is 2021 Transformation Drive, Suite 1500, Entrance B.</p>

<p>For parking, use our <a href="https://innovationstudio-manager.unl.edu/pdf/new-member-orientation-parking-map.pdf">new member orientation parking</a>. Vehicles parked at any other location will be ticketed $50.00.</p>

<p>We'll see you there!</p>

<p>Nebraska Innovation Studio</p>
EMAIL


	VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

	if 	!VALID_EMAIL_REGEX.match(params[:email])
		flash(:danger, "Invalid Email", "Your email address didn't match any known email")
		redirect "new_members/sign_up/#{params[:event_id]}"
	else

		user_info = {"first_name" => params[:first_name],"last_name" => params[:last_name],"email" => params[:email],"university_status" => params[:university_status]}
		user = User.new(user_info)

		# Username parameters:
		# First letter of first name
		# First 5 letters of last name
		# New usernames, append a number on the end starting at 2.
		username_parameters = params[:first_name][0].downcase + params[:last_name][0...5].downcase

		# Create a new user name based on the username_parameters, if the name already exists, increment the name.
		counter = 2
		while true
			if User.find_by(:username => "#{username_parameters + counter.to_s}").nil?
				user.username = "#{username_parameters + counter.to_s}"
				break
			end
			counter = counter + 1
		end

		vehicle1 = Vehicle.new
		license_plate1 = params[:license_plate1]
		state1 = params[:state1]
		make1 = params[:make1]
		model1 = params[:model1]

		vehicle2 = Vehicle.new
		license_plate2 = params[:license_plate2]
		state2 = params[:state2]
		make2 = params[:make2]
		model2 = params[:model2]

		vehicle3 = Vehicle.new
		license_plate3 = params[:license_plate3]
		state3 = params[:state3]
		make3 = params[:make3]
		model3 = params[:model3]

		vehicle1_flag = !license_plate1.blank? && !state1.blank? && !make1.blank? && !model1.blank?

		if vehicle1_flag 
			begin
				vehicle1.license_plate = license_plate1
				vehicle1.state = state1
				vehicle1.make = make1
				vehicle1.model = model1
			rescue => exception
				flash(:error, 'Vehicle 1 Addition Failed', exception.message)
				redirect back
			end
		end

		vehicle2_flag = !license_plate2.blank? && !state2.blank? && make2.blank? && !model2.blank?

		if vehicle2_flag 
			begin
				vehicle2.license_plate = license_plate2
				vehicle2.state = state2
				vehicle2.make = make2
				vehicle2.model = model2
			rescue => exception
				flash(:error, 'Vehicle 2 Addition Failed', exception.message)
				redirect back
			end
		end

		vehicle3_flag = !license_plate3.blank? && !state3.blank? && !make3.blank? && !model3.blank?

		if vehicle3_flag 
			begin
				vehicle3.license_plate = license_plate3
				vehicle3.state = state3
				vehicle3.make = make3
				vehicle3.model = model3
			rescue => exception
				flash(:error, 'Vehicle 3 Addition Failed', exception.message)
				redirect back
			end
		end

		user.space_status = 'expired'
		user.service_space_id = SS_ID

		emergency1 = EmergencyContact.new
		name1 = params[:name1]
		relationship1 = params[:relationship1]
		primary_phone1 = params[:primary_phone1]
		secondary_phone1 = params[:secondary_phone1]

		emergency2 = EmergencyContact.new
		name2 = params[:name2]
		relationship2 = params[:relationship2]
		primary_phone2 = params[:primary_phone2]
		secondary_phone2 = params[:secondary_phone2]

		emergency1_flag = !name1.blank? && !relationship1.blank? && !primary_phone1.blank?

		if emergency1_flag
			begin
				emergency1.name = name1
				emergency1.relationship = relationship1
				emergency1.primary_phone_number = primary_phone1
				emergency1.secondary_phone_number = secondary_phone1
			rescue => exception
				flash(:error, 'Primary Emergency Contact Save Failed', exception.message)
				redirect back
			end
		end

		emergency2_flag = !name2.blank? && !relationship2.blank? && !primary_phone2.blank?

		if emergency2_flag
			begin
				emergency2.name = name2
				emergency2.relationship = relationship2
				emergency2.primary_phone_number = primary_phone2
				emergency2.secondary_phone_number = secondary_phone2
			rescue => exception
				flash(:error, 'Secondary Emergency Contact Save Failed', exception.message)
				redirect back
			end
		end

		User.transaction do
			if emergency1_flag
				emergency1.save
				user.primary_emergency_contact_id = emergency1.id
			end
			if emergency2_flag
				emergency2.save
				user.secondary_emergency_contact_id = emergency2.id
			end
			user.save
			if vehicle1_flag
				vehicle1.user_id = user.id
				vehicle1.save
			end
			if vehicle2_flag
				vehicle2.user_id = user.id
				vehicle2.save
			end
			if vehicle3_flag
				vehicle3.user_id = user.id
				vehicle3.save
			end
		end

		# Creates a record in the event signups
		EventSignup.create(
			:event_id => params[:event_id],
			:name => params[:first_name] + " " + params[:last_name],
			:email => params[:email],
			:user_id => user.id
		)

		Emailer.mail(params[:email], "Nebraska Innovation Studio - #{event.title}", body)

		# flash a message that this works
		flash(:success, "You're signed up!", "Thanks for signing up! Don't forget, orientation is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}. Check your email for more information about the event and where to park.")
		redirect '/new_members/'
	end
  
end

# Code copied from Recaptcha::Adapters::ControllerMethods to resolve issue of this method being private

def verify_recaptcha(options = {})
	options = {model: options} unless options.is_a? Hash
	return true if Recaptcha.skip_env?(options[:env])

	model = options[:model]
	attribute = options.fetch(:attribute, :base)
	recaptcha_response = options[:response] || recaptcha_response_token(options[:action])

	begin
	  verified = if Recaptcha.invalid_response?(recaptcha_response)
		false
	  else
		unless options[:skip_remote_ip]
		  remoteip = (request.respond_to?(:remote_ip) && request.remote_ip) || (env && env['REMOTE_ADDR'])
		  options = options.merge(remote_ip: remoteip.to_s) if remoteip
		end

		success, @_recaptcha_reply =
		  Recaptcha.verify_via_api_call(recaptcha_response, options.merge(with_reply: true))
		success
	  end

	  if verified
		flash.delete(:recaptcha_error) if recaptcha_flash_supported? && !model
		true
	  else
		recaptcha_error(
		  model,
		  attribute,
		  options.fetch(:message) { Recaptcha::Helpers.to_error_message(:verification_failed) }
		)
		false
	  end
	rescue Timeout::Error
	  if Recaptcha.configuration.handle_timeouts_gracefully
		recaptcha_error(
		  model,
		  attribute,
		  options.fetch(:message) { Recaptcha::Helpers.to_error_message(:recaptcha_unreachable) }
		)
		false
	  else
		raise RecaptchaError, 'Recaptcha unreachable.'
	  end
	rescue StandardError => e
	  raise RecaptchaError, e.message, e.backtrace
	end
  end

  def verify_recaptcha!(options = {})
	verify_recaptcha(options) || raise(VerifyError)
  end

  def recaptcha_reply
	@_recaptcha_reply if defined?(@_recaptcha_reply)
  end

  def recaptcha_error(model, attribute, message)
	if model
	  model.errors.add(attribute, message)
	elsif recaptcha_flash_supported?
	  flash[:recaptcha_error] = message
	end
  end

  def recaptcha_flash_supported?
	request.respond_to?(:format) && request.format == :html && respond_to?(:flash)
  end

  # Extracts response token from params. params['g-recaptcha-response-data'] for recaptcha_v3 or
  # params['g-recaptcha-response'] for recaptcha_tags and invisible_recaptcha_tags and should
  # either be a string or a hash with the action name(s) as keys. If it is a hash, then `action`
  # is used as the key.
  # @return [String] A response token if one was passed in the params; otherwise, `''`
  def recaptcha_response_token(action = nil)
	response_param = params['g-recaptcha-response-data'] || params['g-recaptcha-response']
	response_param = response_param[action] if action && response_param.respond_to?(:key?)

	if response_param.is_a?(String)
	  response_param
	else
	  ''
	end
  end

