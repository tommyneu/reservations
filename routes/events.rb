require 'models/event'
require 'models/event_signup'
require 'erb'
require 'recaptcha'

MESSAGE_EVENT_NOT_FOUND = 'message_event_not_found'
MESSAGE_SIGNUP_NOT_ALLOWED = 'message_signup_not_allowed'

Recaptcha.configure do |config|
	config.site_key = CONFIG['reCaptcha']['site_key']
	config.secret_key = CONFIG['reCaptcha']['secret_key']
end

include Recaptcha::Adapters::ControllerMethods
include Recaptcha::Adapters::ViewMethods

def flash_message(message)
    case message
        when MESSAGE_EVENT_NOT_FOUND
            flash(:danger, 'Not Found', 'That event does not exist')
        when MESSAGE_SIGNUP_NOT_ALLOWED
            flash(:danger, 'Signup Restricted', 'That event does not allow signup')
        else
            # invalid message, do nothing
    end
end

get '/events/:event_id.ics' do
	not_found if SS_ID != 1

	# this is an event details page
	begin
		event = Event.includes(:location, :event_type, :event_signups, :location).find(params[:event_id])
	rescue ActiveRecord::RecordNotFound => e
		not_found
	end

	not_found if event.start_time.nil?

	ical_text = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//#{CONFIG['app']['URL']}//#{CONFIG['app']['URL']} Calendar 1.0//EN\n"

	dtstart = event.start_time.utc.strftime('%Y%m%dT%H%M%SZ') # Convert to UTC
	dtend   = event.end_time.utc.strftime('%Y%m%dT%H%M%SZ')   # Convert to UTC

	ical_text += <<~EVENT
		BEGIN:VEVENT
		UID:#{event.id}@#{CONFIG['app']['URL']}
		DTSTAMP:#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}
		DTSTART:#{dtstart}
		DTEND:#{dtend}
		SUMMARY:#{event.title} (#{event.type.description})
	EVENT

	# Add DESCRIPTION if it exists
	ical_text += "DESCRIPTION:#{event.description}\n" if !event.description.empty?

	ical_text += "END:VEVENT\n"
	ical_text += "END:VCALENDAR"

	snake_case_title = event.title.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')

	content_type 'text/calendar; charset=UTF-8'
	headers['Content-Disposition'] = "attachment; filename=\"#{snake_case_title}_#{event.id.to_s}.ics\""
	ical_text
end

get '/events/:event_id/?' do
	# this is an event details page
	begin
		event = Event.includes(:location, :event_type, :event_signups).find(params[:event_id])
	rescue ActiveRecord::RecordNotFound => e
		not_found
	end

	@breadcrumbs << {:text => event.title}
	erb :event_details, :layout => :fixed_61, :locals => {
		:recaptcha => Recaptcha.recaptcha_tags,
		:event => event
	}
end

get '/events/:event_id/sign_up_as_non_member/?' do
	event = Event.includes(:event_type).find_by(:id => params[:event_id])
	if event.nil? || (!(event.end_time.nil?) && event.end_time < Time.now)
		flash_message(MESSAGE_EVENT_NOT_FOUND)
		redirect '/calendar/'
	end
	if !event.signup_allowed_for_type?
	    flash_message(MESSAGE_SIGNUP_NOT_ALLOWED)
        redirect back
	end

	@breadcrumbs << {:text => event.title, :href => event.info_link}
	@breadcrumbs << {:text => 'Sign up as Non-Member'}
	erb :event_signup, :layout => :fixed_61, :locals => {
		:recaptcha => Recaptcha.recaptcha_tags,
		:event => event
	}
end

post '/events/:event_id/sign_up_as_non_member/?' do
	event = Event.includes(:event_type).find_by(:id => params[:event_id])
	if event.nil? || (!(event.end_time.nil?) && event.end_time < Time.now)
		flash_message(MESSAGE_EVENT_NOT_FOUND)
		redirect '/calendar/'
	end
	if event.free_event_type?
		flash(:warning, 'Signup not required', 'This event is a Free Event and is open to anyone. No signup is required.')
		redirect event.info_link
	end
	if params[:name].nil? || params[:name].trim.empty? || params[:email].trim.empty?
		flash(:danger, 'All Fields Required', 'Name and email are both required.')
		redirect back
	end

	if !verify_recaptcha
		flash(:alert, 'Google Recaptcha Verification Failed', 'Please try again.')
		session[:form_data] = params
		redirect back
	end

	VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
	if 	!VALID_EMAIL_REGEX.match(params[:email])
		flash(:danger, "Invalid Email", "Your email address was invalid")
		session[:form_data] = params
		redirect back
	end

	if !event.signup_allowed_for_type?
	    flash_message(MESSAGE_SIGNUP_NOT_ALLOWED)
        redirect back
	end

	if event.event_code.present? && params[:event_code].blank?
		# a code is required to sign up
		flash(:danger, 'Code Required', 'Sorry, a code is required to signup for this event. You have not been signed up for this event.')
		redirect back
	elsif !event.event_code.nil? && !params[:event_code].blank?
		unless params[:event_code] == event.event_code
			# incorrect code provided
			flash(:danger, 'Incorrect Code', 'Sorry, the code you entered is incorrect. You have not been signed up for this event.')
			redirect back
		end
	end

	EventSignup.create(
		:event_id => params[:event_id],
		:name => params[:name],
		:email => params[:email]
	)

	@name = params[:name]
	@event = event

	template_path = "#{ROOT}/views/innovationstudio/email_templates/event_signup_nonmember_email.erb"
	if SS_ID == 8
		template_path = "#{ROOT}/views/engineering_design_hub/email_templates/event_signup_nonmember_email.erb"
	end
	template = File.read(template_path)
	body = ERB.new(template).result(binding)

	Emailer.mail(params[:email], "#{CONFIG['app']['title']} - #{event.title}", body)

	# flash a message that this works
	flash(:success, "You're signed up!", "Thanks for signing up! Don't forget, #{event.title} is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}.")
	redirect event.info_link
end

post '/events/:event_id/sign_up/?' do
	require_login

	# check that is a valid event
	event = Event.includes(:event_type).find_by(:service_space_id => SS_ID, :id => params[:event_id])

	if event.nil? || (!(event.end_time.nil?) && event.end_time < Time.now)
		# that event does not exist
		flash_message(MESSAGE_EVENT_NOT_FOUND)
		redirect '/calendar/'
	end

	if !event.max_signups.nil? && event.signups.count >= event.max_signups
		# that event is full
		flash(:danger, 'Event Full', 'Sorry, that event is full.')
		redirect back
	end

	if !event.signup_allowed_for_type?
	    flash_message(MESSAGE_SIGNUP_NOT_ALLOWED)
        redirect back
	end

	if event.event_code.present? && params[:event_code].blank?
		# a code is required to sign up
		flash(:danger, 'Code Required', 'Sorry, a code is required to signup for this event. You have not been signed up for this event.')
		redirect back
	elsif !event.event_code.nil? && !params[:event_code].blank?
		unless params[:event_code] == event.event_code
			# incorrect code provided
			flash(:danger, 'Incorrect Code', 'Sorry, the code you entered is incorrect. You have not been signed up for this event.')
			redirect back
		end
	end

	EventSignup.create(
		:event_id => params[:event_id],
		:name => @user.full_name,
		:user_id => @user.id,
		:email => @user.email
	)

	if !event.free_event_type?
		@event = event

		if @user.email && !@user.email.empty?
			template_path = "#{ROOT}/views/engineering_design_hub/email_templates/timeless_event_signup_email.erb"
			success_message = "Thanks for signing up! You may attend during any regular operating hours."
			if SS_ID == 8
				if event.start_time != nil
					template_path = "#{ROOT}/views/engineering_design_hub/email_templates/event_signup_email.erb"
					success_message = "Thanks for signing up! Don't forget, #{event.title} is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}."
				end
			else
				template_path = "#{ROOT}/views/innovationstudio/email_templates/event_signup_email.erb"
				success_message = "Thanks for signing up! Don't forget, #{event.title} is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}."
			end
			template = File.read(template_path)
			body = ERB.new(template).result(binding)
			
			Emailer.mail(@user.email, "#{CONFIG['app']['title']} - #{event.title}", body)
		end

		# flash a message that this works
		flash(:success, "You're signed up!", success_message)
		redirect back
	else
		# flash a message that this works
		flash(:success, "Event Marked", "This free event has been marked on your homepage.")
		redirect back
	end
end

post '/events/:event_id/remove_signup/?' do
	require_login

	# get the event
	event = Event.includes(:event_type).where(:id => params[:event_id]).first

	# check that the signup exists
	signup = EventSignup.where(:event_id => params[:event_id], :user_id => @user.id).first

	if signup.nil?
		flash :alert, 'Not Found', 'That signup was not found.'
		redirect '/home/'
	end
	signup.delete

	header = event.free_event_type? ? 'Event Removed' : 'Signup Removed'
	message = event.free_event_type? ? "#{event.title} has been removed from your calendar." : "Your signup for #{event.title} has been removed."

	flash :success, header, message
	redirect '/home/'
end

post '/events/:event_id/confirm_trainer/?' do
	require_login

	# get the event
	event = Event.includes(:event_type).where(:id => params[:event_id]).first

	if event.trainer_id != @user.id && event.trainer_2_id != @user.id && event.trainer_3_id != @user.id
		@breadcrumbs << {:text => 'Not Authorized'}
		erb 'You are not authorized to preform that action', :layout => :fixed_61
	else
		if event.trainer_id == @user.id
			event.trainer_confirmed = 1
			event.save
		end
	
		if event.trainer_2_id == @user.id
			event.trainer_2_confirmed = 1
			event.save
		end
	
		if event.trainer_3_id == @user.id
			event.trainer_3_confirmed = 1
			event.save
		end
	
		header = 'Training Confirmed'
		message = "Your training #{event.title} has been confirmed."
	
		flash :success, header, message
		redirect '/home/'
	end
end

# Code copied from Recaptcha::Adapters::ControllerMethods to resolve issue of this method being private

def verify_recaptcha(options = {})
  options = { model: options } unless options.is_a? Hash
  return true if CONFIG['reCaptcha']['site_key'].nil? || CONFIG['reCaptcha']['site_key'].empty?
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
