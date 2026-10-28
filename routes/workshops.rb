require 'models/resource'
require 'models/reservation'
require 'models/event'
require 'models/event_type'
require 'models/event_signup'
require 'models/space_hour'
require 'erb'

get '/workshops/?' do
	@breadcrumbs << {:text => 'Workshops'}
	require_login

	events_advanced = nil
	events_creation = nil

	workshop_id = EventType.find_by(:description => 'General Workshop', :service_space_id => SS_ID).id
	events_general = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
					where('start_time >= ?', Time.now).order(:start_time => :asc).all

	if SS_ID == 1
		workshop_id = EventType.find_by(:description => 'Advanced Skill-Based Workshop', :service_space_id => SS_ID).id
		events_advanced = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
						where('start_time >= ?', Time.now).order(:start_time => :asc).all

		workshop_id = EventType.find_by(:description => 'Creation Workshop', :service_space_id => SS_ID).id
		events_creation = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
						where('start_time >= ?', Time.now).order(:start_time => :asc).all

		workshop_id = EventType.find_by(:description => 'General Workshop', :service_space_id => SS_ID).id
		events_general = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
						where('start_time >= ?', Time.now).order(:start_time => :asc).all
	end

	erb :workshops, :layout => :fixed_61, :locals => {
		:events_advanced => events_advanced,
		:events_creation => events_creation,
		:events_general => events_general
	}
end

post '/workshops/sign_up/:event_id/?' do
	require_login

	workshop_id_advanced = nil
	workshop_id_creation = nil
	workshop_id_general = EventType.find_by(:description => 'General Workshop', :service_space_id => SS_ID).id
	if SS_ID == 1
		workshop_id_advanced = EventType.find_by(:description => 'Advanced Skill-Based Workshop', :service_space_id => SS_ID).id
		workshop_id_creation ||= EventType.find_by(:description => 'Creation Workshop', :service_space_id => SS_ID).id
	end

	# check that is a valid event
	event = Event.find_by(:service_space_id => SS_ID, :event_type_id => workshop_id_advanced, :id => params[:event_id])
	event ||= Event.find_by(:service_space_id => SS_ID, :event_type_id => workshop_id_creation, :id => params[:event_id])
	event ||= Event.find_by(:service_space_id => SS_ID, :event_type_id => workshop_id_general, :id => params[:event_id])

	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', "That event does not exist #{workshop_id}")
		redirect '/workshops/'
	end

	if !event.max_signups.nil? && event.signups.count >= event.max_signups
		# that event is full
		flash(:danger, 'Event Full', 'Sorry, that event is full.')
		redirect '/workshops/'
	end

	if event.event_code.present? && params[:event_code].blank?
		# a code is required to sign up
		flash(:danger, 'Code Required', 'Sorry, a code is required to signup for this event. You have not been signed up for this event.')
		redirect '/workshops/'
	elsif !event.event_code.nil? && !params[:event_code].blank?
		unless params[:event_code] == event.event_code
			# incorrect code provided
			flash(:danger, 'Incorrect Code', 'Sorry, the code you entered is incorrect. You have not been signed up for this event.')
			redirect '/workshops/'
		end
	end

	EventSignup.create(
		:event_id => params[:event_id],
		:name => @user.full_name,
		:user_id => @user.id,
		:email => @user.email
	)

	@event = event

	if @user.email && !@user.email.empty?
		template_path = "#{ROOT}/views/innovationstudio/email_templates/workshop_signup_email.erb"
		if SS_ID == 8
			template_path = "#{ROOT}/views/engineering_design_hub/email_templates/workshop_signup_email.erb"
		end
		template = File.read(template_path)
		body = ERB.new(template).result(binding)
		
		Emailer.mail(@user.email, "#{CONFIG['app']['title']} - #{event.title}", body)
	end

	# flash a message that this works
	flash(:success, "You're signed up!", "Thanks for signing up! Don't forget, #{event.title} is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}.")
	redirect '/workshops/'
end

