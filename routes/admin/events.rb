require 'rest-client'
require 'models/event'
require 'models/event_type'
require 'models/location'
require 'models/resource'
require 'models/resource_authorization'
require 'models/preset_event'
require 'models/event_authorization'
require 'models/preset_events_has_resource_reservation'
require 'models/attended_orientation'

before '/admin/events*' do
	unless has_permission?(Permission::MANAGE_EVENTS) || has_permission?(Permission::EVENTS_ADMIN_READ_ONLY)
		raise Sinatra::NotFound
	end
end

before '/admin/events/:event_id/(create|edit|delete)*?' do
    unless has_permission?(Permission::MANAGE_EVENTS)
        raise Sinatra::NotFound
    end
end

get '/admin/events/?' do
	@breadcrumbs << {:text => 'Admin Events'}
	page = params[:page]
	page = page.to_i >= 1 ? page.to_i : 1
	page_size = 10
	tab = ['upcoming', 'past', 'timeless'].include?(params[:tab]) ? params[:tab] : 'upcoming'
	preset_events = PresetEvents.where(:service_space_id => SS_ID).order(event_name: :asc).all.to_a
	event_type = params[:event_type]
	event_area = params[:event_area]
	trainer_filter = params[:trainer_filter]

	case tab
	when 'past'
		where_clause = 'start_time < ?', Time.now
		order_clause = {:start_time => :desc}
	when 'upcoming'
		where_clause = 'start_time >= ?', Time.now
		order_clause = {:start_time => :asc}
	else
		where_clause = 'start_time IS NULL', Time.now
	end

	iterator = Event.includes(:event_signups).where(:service_space_id => SS_ID).where(where_clause)

	# Redefine the iterator variable if there is an event type filter applied
	unless event_type.nil? || event_type.length == 0
		iterator = iterator.where(:event_type_id => event_type)
	end
	unless event_area.nil? || event_area.length == 0
		if event_area == 'General'
			iterator = iterator.where(:area => ['General', nil]) # Nil is also General
		else
			iterator = iterator.where(:area => event_area)
		end
	end

	unless trainer_filter.nil? || trainer_filter.length == 0
		iterator = iterator.joins(
			"LEFT JOIN users u1 ON events.trainer_id = u1.id
			LEFT JOIN users u2 ON events.trainer_2_id = u2.id
			LEFT JOIN users u3 ON events.trainer_3_id = u3.id"
		).where(
			"LOWER(u1.username) LIKE :filter OR LOWER(u1.first_name) LIKE :filter OR LOWER(u1.last_name) LIKE :filter
			OR LOWER(u2.username) LIKE :filter OR LOWER(u2.first_name) LIKE :filter OR LOWER(u2.last_name) LIKE :filter
			OR LOWER(u3.username) LIKE :filter OR LOWER(u3.first_name) LIKE :filter OR LOWER(u3.last_name) LIKE :filter",
			filter: "%#{trainer_filter.downcase}%"
		)
	end
	
	erb :'admin/events', :layout => :fixed_61, :locals => {
		:events => iterator.order(order_clause).limit(page_size).offset((page-1)*page_size).all,
		:total_pages => (iterator.count.to_f / page_size).ceil,
		:page => page,
		:tab => tab,
		:preset_events => preset_events,
		:event_type => event_type,
		:event_area => event_area,
		:trainer_filter => trainer_filter
	}
end

get '/admin/events/:event_id/signup_list/?' do
	@breadcrumbs << {:text => 'Admin Events', :href => '/admin/events/'} << {text: 'Signup List'}
	event = Event.includes(:event_signups).find_by(:id => params[:event_id], :service_space_id => SS_ID)
	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/admin/events/'
	end

	erb :'admin/signup_list', :layout => :fixed_61, :locals => {
		:event => event,
		:event_type_id => event.event_type_id
	}
end

post '/admin/events/:event_id/signup_list/?' do
	new_member_orientation_id = EventType.find_by(:description => 'New Member Orientation', :service_space_id => SS_ID).id
	event = Event.includes(:event_signups).find_by(:id => params[:event_id], :service_space_id => SS_ID)
	tools = EventAuthorization.where(:event_id => params[:event_id])

	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/admin/events/'
	end

	if event.event_type_id == new_member_orientation_id
		# removes users from attended orientation master list if they are unchecked
		event.signups.each do |signup|
			unless params.has_key?("attendance_#{signup.id}") && params["attendance_#{signup.id}"] == 'on'
				user_id = signup.user_id
				if signup.attended == 1
					orientation_attendee = AttendedOrientation.find_by(:user_id => user_id)
					if !orientation_attendee.nil?
						orientation_attendee.delete
					end
					signup.attended = 0
					signup.save
				end
			end
		end

		# adds users to attended orienttaion master list if checked
		params.each do |key, value|

			if key.start_with?('attendance_') && value == 'on'

				signup_id = key.split('attendance_')[1].to_i
				signup_record = EventSignup.find_by(:id => signup_id)

				unless signup_record == nil
					user = User.find_by(:id => signup_record.user_id, :service_space_id => SS_ID)

					if signup_record.attended == 0
						signup_record.attended = 1
						signup_record.save
					end

          if event.start_time == nil && SS_ID == 8
            end_time = Time.now
          else 
            end_time = event.end_time
          end

					if !user.nil? && event.event_type_id == new_member_orientation_id
						# Check if user is already on list
						unless AttendedOrientation.exists?(user_id: user.id)
							AttendedOrientation.create(
								:user_id => user.id,
								:name => user.full_name,
								:date_attended => end_time,
								:university_status => user.university_status,
								:user_email => user.email,
								:event_id => event.id
							)
							user.send_attended_orientation_email
						end

					end
				end
			end
		end
	end

	# checks first if the deletion checkbox was selected and deletes the signup record aswell as the key
	params.each do |key, value|

		if key.start_with?('deletion_') && value == 'on'

			signup_id = key.split('deletion_')[1].to_i
			signup_record = EventSignup.find_by(:id => signup_id)

			unless signup_record == nil
				user = User.find_by(:id => signup_record.user_id, :service_space_id => SS_ID)
				if !user.nil? && signup_record.attended == 1 && event.event_type_id == new_member_orientation_id
					orientation_attendance = AttendedOrientation.find_by(:user_id => user.id)
					if !orientation_attendance.nil?
						orientation_attendance.destroy
					end
				end
				signup_record.destroy
			end
		end
	end

	# remove the given tool permissions when the attended member is unchecked 
	event.signups.each do |signup|
		unless params.has_key?("attendance_#{signup.id}") && params["attendance_#{signup.id}"] == 'on' 
			user_id = signup.user_id
			if signup.attended == 1
				tools.each do |tool|
					tool_id =  tool.resource_id 
					auth_tool=ResourceAuthorization.find_by(:user_id => user_id, :resource_id => tool_id)
					if !auth_tool.authorized_event.nil? && auth_tool.authorized_event  == event.id
						ResourceAuthorization.find_by(:user_id => user_id, :resource_id => tool_id, :authorized_event => event.id ).delete
					end
				end 
				signup.attended = 0
				signup.save
			end 
		end	
	end

	#  add new tool permissions for checked members in signup list
	params.each do |key, value|
		if key.start_with?('attendance_') && value == 'on'

			signup_id = key.split('attendance_')[1].to_i
			signup_record = EventSignup.find_by(:id => signup_id)
			user = User.find_by(:id => signup_record.user_id, :service_space_id => SS_ID)

			if signup_record.attended == 0
				signup_record.attended = 1
				signup_record.save
			end

			if !user.nil?
				tools.each do |tool|
					tool_id =  tool.resource_id 
					# check if the user already has permission for this tool
					unless user.authorized_resource_ids.include?(tool_id)
						ResourceAuthorization.create(
							:user_id => user.id,
							:resource_id => tool_id,
							:authorized_date => Time.now,
							:authorized_event => signup_record.event_id
						)
					end
				end
			end
		end
	end

	flash :success, 'Event\'s Signup List Updated', "#{event.title.rstrip}'s Signup List have been updated."
	redirect '/admin/events/'
end

def event_type_allow_signup_deletions(event_type_id)
	# We used to have code here to only allow deletes on new membership orientation events and HRC events
	return true;
end

get '/admin/events/create/?' do
	@breadcrumbs << {:text => 'Admin Events', :href => '/admin/events/'} << {text: 'Create Event'}
	hrc_training_id = nil
	if SS_ID == 1
		hrc_training_id = EventType.find_by(:description => 'HRC Training', :service_space_id => SS_ID).id
	end
	tools = Resource.where(:service_space_id => SS_ID, :is_reservable => true).order(:name => :asc).all.to_a
	all_tools = Resource.where(:service_space_id => SS_ID).order(:name).all.to_a
    all_tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	all_tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	
	if params[:preset_id].nil? || Integer(params[:preset_id]) == 0
		
		erb :'admin/new_event', :layout => :fixed_61, :locals => {
			:event => Event.new,
			:mode => 'create',
			:types => EventType.where(:service_space_id => SS_ID).all,
			:trainers => User.where(:is_trainer => 1, :service_space_id => SS_ID).all,
			:locations => Location.where(:service_space_id => SS_ID).all,
			:tools => tools,
			:all_tools => all_tools,
			:preset_event => nil,
			:on_unl_events => false,
			:on_main_calendar => false,
			:duration => 60,
			:hrc_training_id => hrc_training_id
		}
	else
		preset = PresetEvents.find_by(:id => params[:preset_id])
		event = Event.new
		event.title = preset.event_name
		event.description = preset.description
		event.event_type_id = preset.event_type_id
		event.area = preset.area
		event.max_signups = preset.max_signups
		
		erb :'admin/new_event', :layout => :fixed_61, :locals => {
			:event => event,
			:mode => 'create',
			:types => EventType.where(:service_space_id => SS_ID).all,
			:trainers => User.where(:is_trainer => 1, :service_space_id => SS_ID).all,
			:locations => Location.where(:service_space_id => SS_ID).all,
			:tools => tools,
			:all_tools => all_tools,
			:preset_event => preset,
			:on_unl_events => false,
			:on_main_calendar => false,
			:duration => preset.duration,
			:hrc_training_id => hrc_training_id
		}
	end	
end

post '/admin/events/create/?' do

	if params[:title].blank?
		flash :error, 'Error', 'Please enter event title'
		redirect back
	end

	if params[:timeless_event_checkbox] == "on"
		if params['reserve_tool'] == 'on'
			flash :error, 'Error', 'Reservation not allowed for timeless event'
			redirect back
		end
	end

	if params[:location] == 'new'
		# this is a new location, we must create it!
		location = Location.create(params[:new_location].merge({
			:service_space_id => SS_ID
		}))
		params[:location] = location.id
	end

	if params[:timeless_event_checkbox] != "on"
		params[:start_date].keys.each do |date_key|
			begin
				this_date = {
					:start_date => params[:start_date][date_key],
					:end_date => params[:start_date][date_key],
					:start_time_hour => params[:start_time_hour][date_key],
					:start_time_minute => params[:start_time_minute][date_key],
					:start_time_am_pm => params[:start_time_am_pm][date_key],
					:end_time_hour => params[:end_time_hour][date_key],
					:end_time_minute => params[:end_time_minute][date_key],
					:end_time_am_pm => params[:end_time_am_pm][date_key],
				}
			rescue
				flash :error, 'Error', 'Missing info on your dates'
				redirect back
			end

			event = Event.new
			event.set_image_data(params)
			event.set_data(params, this_date)

			set_up_event(params, event)
		end
	else
		event = Event.new
		event.set_image_data(params)
		event.set_data(params, {})

		set_up_event(params, event)
	end


	# notify that it worked
	flash(:success, 'Event Created', "Your #{params[:description]}: #{params[:title]} has been created.")
	redirect '/admin/events/'
end

def set_up_event(params, event)
	if params[:timeless_event_checkbox] != "on"
		if event.end_time.in_time_zone < event.start_time.in_time_zone
			event.delete
			flash :alert, "Start and end times create a negative duration.", "Sorry, the selected times cannot be used to create an event. Please try different day or time. Please double check your event information."
			redirect back
		end

		if params.has_key?('reserve_tool') && params['reserve_tool'] == 'on' && !params[:tools].nil?
			# check for possible other reservations during this time period
			date = event.start_time.midnight.in_time_zone
			params[:tools].each do |tool_id|
				other_reservations = Reservation.where(:resource_id => tool_id).in_day(date).all
				other_reservations.each do |reservation|
					if event.start_time.in_time_zone < reservation.end_time.in_time_zone && reservation.start_time.in_time_zone < event.end_time.in_time_zone
							event.delete
							flash :alert, "A tool is being used.", "Sorry, a selected tool is reserved during that time period. Please try different day or time."
							redirect back
					end
				end

				# we need to create a reservation for the tool on the appropriate time
				Reservation.create(
					:resource_id => tool_id,
					:event_id => event.id,
					:start_time => event.start_time,
					:end_time => event.end_time,
					:is_training => true,
					:user_id => nil
				)
			end
		end
	end

	if params.checked?('authorize_tools_checkbox') and !params[:specific_tools].nil?
		params[:specific_tools].each do |id|
			event_authorization = EventAuthorization.create(:resource_id => id,:event_id => event.id)
		end
	end

	if params.checked?('export_to_unl_events')
		# first create the location, if necessary
		if event.location.unl_events_id.nil?
			post_params = event.location.attributes.merge(:api_token => CONFIG['unl_events_api_token'])
			RestClient.post("#{CONFIG['unl_events_api_url']}location/create/", post_params) do |response, request, result|
				case response.code
				when 200
					event.location.unl_events_id = JSON.parse(response.body)['id']
					event.location.save
				else
					flash :error, 'Location Not Posted to UNL Events', "We had an issue creating the location on UNL Events. Please go to events.unl.edu/manager to create your event."
				end
			end
		end

		# send the event up
		post_params = {
			:title => params[:title],
			:description => params[:description],
			:trainer => event.trainer_id,
			:location => event.location.unl_events_id,
			:start_time => event.start_time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S'),
			:end_time => event.end_time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S'),
			:api_token => CONFIG['unl_events_api_token']
		}

		if params.checked?('consider_for_unl_main')
			post_params['send_to_main'] =  'yes'
		end

		RestClient.post("#{CONFIG['unl_events_api_url']}#{CONFIG['unl_events_api_calendar']}/create/", post_params) do |response, request, result|
			case response.code
			when 200
				flash :success, 'Event Posted to UNL Events', "The event can now be found on the NIS UNL Events calendar."
				event.unl_events_id = JSON.parse(response.body)['id']
				event.save
			else
				flash :error, 'Event Not Posted to UNL Events', "There was a problem posting to UNL Events. You should check out your UNL Events calendar to see if your event made it."
			end
		end
	end

	# email the assigned trainer
	trainers_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_id)
	trainers_2_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_2_id)
	trainers_3_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_3_id)

	trainers_to_email.each do |user|
		user.notify_trainer_of_new_event(event)
	end
	trainers_2_to_email.each do |user|
		user.notify_trainer_of_new_event(event)
	end
	trainers_3_to_email.each do |user|
		user.notify_trainer_of_new_event(event)
	end
end

get '/admin/events/:event_id/edit/?' do
	@breadcrumbs << {:text => 'Admin Events', :href => '/admin/events/'} << {text: 'Edit Event'}
	hrc_training_id = nil
	if SS_ID == 1
		hrc_training_id = EventType.find_by(:description => 'HRC Training', :service_space_id => SS_ID).id
	end
	event = Event.includes(:event_type, :location, :reservation => :resource).find_by(:id => params[:event_id], :service_space_id => SS_ID)
	all_tools = Resource.where(:service_space_id => SS_ID).order(:name).all.to_a
	all_tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	event_authorized_tools = EventAuthorization.joins(:event).where('event_id = ?', event.id)
    authorized_tools_ids = Array.new

    event_authorized_tools.each do |tool|
        authorized_tools_ids.append(tool.resource_id)
    end

	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/admin/events/'
	end

	on_unl_events = false
	on_main_calendar = false
	unless event.unl_events_id.nil?
		get_params = {
			:api_token => CONFIG['unl_events_api_token']
		}
		RestClient.get("#{CONFIG['unl_events_api_url']}#{CONFIG['unl_events_api_calendar']}/event/#{event.unl_events_id}/", {:params => get_params}) do |response, request, result, &block|
			if response.code == 200
				on_unl_events = true
				if JSON.parse(response.body)['on_main_calendar']
					on_main_calendar = true
				end
			end
		end
	end

	tools = Resource.where(:service_space_id => SS_ID, :is_reservable => true).order(:name => :asc).all.to_a
	tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	if event.start_time != nil
		erb :'admin/new_event', :layout => :fixed_61, :locals => {
			:event => event,
			:mode => 'edit',
			:types => EventType.where(:service_space_id => SS_ID).all,
			:trainers => User.where(:is_trainer => 1, :service_space_id => SS_ID).all,
			:locations => Location.where(:service_space_id => SS_ID).all,
			:tools => tools,
			:all_tools => all_tools,
			:authorized_tools_ids => authorized_tools_ids,
			:on_unl_events => on_unl_events,
			:on_main_calendar => on_main_calendar,
			:duration => ((event.end_time - event.start_time)/60.0).round,
			:hrc_training_id => hrc_training_id
		}
	else
		erb :'admin/new_event', :layout => :fixed_61, :locals => {
			:event => event,
			:mode => 'edit',
			:types => EventType.where(:service_space_id => SS_ID).all,
			:trainers => User.where(:is_trainer => 1, :service_space_id => SS_ID).all,
			:locations => Location.where(:service_space_id => SS_ID).all,
			:tools => tools,
			:all_tools => all_tools,
			:authorized_tools_ids => authorized_tools_ids,
			:on_unl_events => on_unl_events,
			:on_main_calendar => on_main_calendar,
			:duration => 0,
			:hrc_training_id => hrc_training_id
		}
	end
end

post '/admin/events/:event_id/edit/?' do
	event = Event.find_by(:id => params[:event_id], :service_space_id => SS_ID)
	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/admin/events/'
	end

	if  params[:title].blank?
		flash :error, 'Error', 'Please enter event title'
		redirect back
	end 

	if params[:timeless_event_checkbox] == "on"
		if params['reserve_tool'] == 'on'
			flash :error, 'Error', 'Reservation not allowed for timeless event'
			redirect back
		end
	end

	old_trainer = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_id)
	old_trainer_2 = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_2_id)
	old_trainer_3 = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_3_id)

    # remember original start/end times
    original_event_start_time = event.start_time
    original_event_end_time = event.end_time

	if params[:location] == 'new'
		# this is a new location, we must create it!
		location = Location.create(params[:new_location].merge({
			:service_space_id => SS_ID
		}))
		params[:location] = location.id
	end

	if params.checked?('remove_image')
		event.remove_image_data
	else
		event.set_image_data(params)
	end

	if params[:timeless_event_checkbox] != "on"
		params[:start_date].keys.each do |date_key|
			begin
				this_date = {
					:start_date => params[:start_date][date_key],
					:end_date => params[:start_date][date_key],
					:start_time_hour => params[:start_time_hour][date_key],
					:start_time_minute => params[:start_time_minute][date_key],
					:start_time_am_pm => params[:start_time_am_pm][date_key],
					:end_time_hour => params[:end_time_hour][date_key],
					:end_time_minute => params[:end_time_minute][date_key],
					:end_time_am_pm => params[:end_time_am_pm][date_key],
				}
			rescue
				flash :error, 'Error', 'Missing info on your dates'
				redirect back
			end

			event.set_data(params, this_date)
			edit_up_event(params, event, original_event_start_time, original_event_end_time, old_trainer, old_trainer_2, old_trainer_3)
		end
	else
		event.set_data(params, {})
		edit_up_event(params, event, original_event_start_time, original_event_end_time, old_trainer, old_trainer_2, old_trainer_3)
	end


	# notify that it worked
	flash(:success, 'Event Updated', "Your #{event.type.description}: #{event.title} has been updated.")
	redirect '/admin/events/'
end

def edit_up_event(params, event, original_event_start_time, original_event_end_time, old_trainer, old_trainer_2, old_trainer_3)

	if params[:timeless_event_checkbox] != "on"
		if event.end_time.in_time_zone < event.start_time.in_time_zone
			event.update(start_time: original_event_start_time, end_time: original_event_end_time)
			flash :alert, "Start and end times create a negative duration.", "Sorry, the selected times cannot be used to create an event. Please try different day or time. Please double check your event information."
			redirect back
		end 

		# check the tool reservation for this
		checked = params.checked?('reserve_tool') && !params[:tools].nil?

		if (checked)
			# check for possible other reservations during this time period
			date = event.start_time.midnight.in_time_zone
			params[:tools].each do |tool_id|
				other_reservations = Reservation.where(:resource_id => tool_id).in_day(date).all
				other_reservations.each do |reservation|
					# ignore reservations for same the event
					next if reservation.event_id == event.id

					if event.start_time.in_time_zone < reservation.end_time.in_time_zone && reservation.start_time.in_time_zone < event.end_time.in_time_zone
						# reset event times since reservation failed
						event.update(start_time: original_event_start_time, end_time: original_event_end_time)

						# show error and display event form
						flash :alert, "A tool is being used.", "Sorry, a selected tool is reserved during that time period. Please try different day or time."
						redirect back
					end
				end
			end
		end

		if event.has_reservation && checked
			# create or update selected tool reservations
			params[:tools].each do |tool_id|
				if event.has_tool_reservation(tool_id)
					# update the reservation
					event.reservation.update(
						:resource_id => params[tool_id],
						:event_id => event.id,
						:start_time => event.start_time,
						:end_time => event.end_time,
						:is_training => true,
						:user_id => nil
					)
				else
					# create the reservation
					Reservation.create(
						:resource_id => tool_id,
						:event_id => event.id,
						:start_time => event.start_time,
						:end_time => event.end_time,
						:is_training => true,
						:user_id => nil
					)
				end
			end

			# remove any old tool reservations
			event.reservation.each do |r|
				if !r.resource.nil? && !params[:tools].include?(r.resource.id)
					r.delete
				end
			end
		elsif event.has_reservation && !checked
			# remove all event reservations
			event.reservation.each do |r|
				r.delete
			end
		elsif !event.has_reservation && checked
			params[:tools].each do |tool_id|
				# create the reservation
				Reservation.create(
					:resource_id => tool_id,
					:event_id => event.id,
					:start_time => event.start_time,
					:end_time => event.end_time,
					:is_training => true,
					:user_id => nil
				)
			end
		end
	end

	delete_old_authorizations = EventAuthorization.where(event_id: event.id).all
    delete_old_authorizations.destroy_all

	if params.checked?('authorize_tools_checkbox') and !params[:specific_tools].nil?
		params[:specific_tools].each do |id|
			event_authorization = EventAuthorization.create(:resource_id => id,:event_id => event.id)
		end
	end

	if params.checked?('export_to_unl_events')
		on_unl_events = false
		unless event.unl_events_id.nil?
			get_params = {
				:api_token => CONFIG['unl_events_api_token']
			}
			RestClient.get("#{CONFIG['unl_events_api_url']}#{CONFIG['unl_events_api_calendar']}/event/#{event.unl_events_id}/", {:params => get_params}) do |response, request, result, &block|
				if response.code == 200
					on_unl_events = true
					if JSON.parse(response.body)['on_main_calendar']
						on_main_calendar = true
					end
				end
			end
		end

		if !on_unl_events
			# first create the location, if necessary
			if event.location.unl_events_id.nil?
				post_params = event.location.attributes.merge(:api_token => CONFIG['unl_events_api_token'])
				RestClient.post("#{CONFIG['unl_events_api_url']}location/create/", post_params) do |response, request, result|
					case response.code
					when 200
						event.location.unl_events_id = JSON.parse(response.body)['id']
						event.location.save
					else
						flash :error, 'Location Not Posted to UNL Events', "We had an issue creating the location on UNL Events. Please go to events.unl.edu/manager to create your event."
					end
				end
			end

			# send the event up
			post_params = {
				:title => params[:title],
				:description => params[:description],
				:trainer => event.trainer_id,
				:location => event.location.unl_events_id,
				:start_time => event.start_time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S'),
				:end_time => event.end_time.in_time_zone.strftime('%Y-%m-%d %H:%M:%S'),
				:api_token => CONFIG['unl_events_api_token']
			}

			if params.checked?('consider_for_unl_main')
				post_params['send_to_main'] =  'yes'
			end

			RestClient.post("#{CONFIG['unl_events_api_url']}#{CONFIG['unl_events_api_calendar']}/create/", post_params) do |response, request, result|
				case response.code
				when 200
					flash :success, 'Event Posted to UNL Events', "The event can now be found on the NIS UNL Events calendar."
					event.unl_events_id = JSON.parse(response.body)['id']
					event.save
				else
					flash :error, 'Event Not Posted to UNL Events', "There was a problem posting to UNL Events. You should check out your UNL Events calendar to see if your event made it."
				end
			end
		else
			post_params = {
				:title => params[:title],
				:description => params[:description],
				:api_token => CONFIG['unl_events_api_token']
			}

			if params.checked?('consider_for_unl_main')
				post_params['send_to_main'] = 'yes'
			end

			RestClient.post("#{CONFIG['unl_events_api_url']}#{CONFIG['unl_events_api_calendar']}/event/#{event.unl_events_id}/", post_params) do |response, request, result, &block|
				case response.code
				when 200
					flash :success, 'Event Posted to UNL Events', "The event details were updated on the NIS UNL Events calendar."
					event.unl_events_id = JSON.parse(response.body)['id']
					event.save
				else
					flash :error, 'Event Not Posted to UNL Events', "There was a problem posting to UNL Events. You should check out your UNL Events calendar to see if your event is OK."
				end
			end
		end
	end

	trainer_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_id)
	trainer_2_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_2_id)
	trainer_3_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_3_id)

	# if trainer has changed
	if(old_trainer != trainer_to_email)

		# notify old trainer of their removal
		old_trainer.each do |user|
			user.notify_trainer_of_removal_from_event(event)
		end

		# notify new trainer of their addition
		trainer_to_email.each do |user|
			user.notify_trainer_of_new_event(event)
		end

		# remove previous trainer confirmation
		event.trainer_confirmed = 0
		event.save
	else
		trainer_to_email.each do |user|
			user.notify_trainer_of_modified_event(event)
		end
	end

	# if trainer has changed
	if(old_trainer_2 != trainer_2_to_email)

		# notify old trainer of their removal
		old_trainer_2.each do |user|
			user.notify_trainer_of_removal_from_event(event)
		end

		# notify new trainer of their addition
		trainer_2_to_email.each do |user|
			user.notify_trainer_of_new_event(event)
		end

		# remove previous trainer confirmation
		event.trainer_2_confirmed = 0
		event.save
	else
		trainer_2_to_email.each do |user|
			user.notify_trainer_of_modified_event(event)
		end
	end

	# if trainer has changed
	if(old_trainer_3 != trainer_3_to_email)

		# notify old trainer of their removal
		old_trainer_3.each do |user|
			user.notify_trainer_of_removal_from_event(event)
		end

		# notify new trainer of their addition
		trainer_3_to_email.each do |user|
			user.notify_trainer_of_new_event(event)
		end

		# remove previous trainer confirmation
		event.trainer_3_confirmed = 0
		event.save
	else
		trainer_3_to_email.each do |user|
			user.notify_trainer_of_modified_event(event)
		end
	end
end

post '/admin/events/:event_id/delete/?' do
	event = Event.find_by(:id => params[:event_id], :service_space_id => SS_ID)
	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/admin/events/'
	end

	trainer_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_id)
	trainer_2_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_2_id)
	trainer_3_to_email = User.where(:service_space_id => SS_ID).where('id = ?', event.trainer_3_id)

	trainer_to_email.each do |user|
		user.notify_trainer_of_deleted_event(event)
	end
	trainer_2_to_email.each do |user|
		user.notify_trainer_of_deleted_event(event)
	end
	trainer_3_to_email.each do |user|
		user.notify_trainer_of_deleted_event(event)
	end
	
	delete_old_authorizations = EventAuthorization.where(event_id: event.id).all
    delete_old_authorizations.destroy_all

	event.destroy

	flash(:success, 'Event Deleted', "Your event #{event.title} has been deleted. All signups on this event have also been removed, and if a reservation was attached, it also has been removed.")
	redirect '/admin/events/'
end

get '/admin/events/presets/?' do
	@breadcrumbs << {:text => 'Manage Event Presets', :href => '/admin/events/presets'}
	preset_events = PresetEvents.where(:service_space_id => SS_ID).order(event_name: :asc).all.to_a
	event_type_objects = EventType.where(:service_space_id => SS_ID)
	event_types = {}
	event_type_objects.each do |type|
		event_types[type.id] = type.description
	end
	
	erb :'admin/event_presets', :layout => :fixed_61, :locals => {
		:preset_events => preset_events,
		:event_types => event_types
	}
end

get '/admin/events/presets/create/?' do
	@breadcrumbs << {:text => 'Manage Event Presets', :href => '/admin/events/presets/'}  << {text: 'Create Preset Event'}
	event_types = EventType.where(:service_space_id => SS_ID).all
	tools = Resource.where(:service_space_id => SS_ID).order(:name).all.to_a
	tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	reservable_tools = Resource.where(:service_space_id => SS_ID, :is_reservable => true).order(:name => :asc).all.to_a
	reservable_tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	
	erb :'admin/new_preset_event', :layout => :fixed_61, :locals => {
		:preset_event => PresetEvents.new,
		:event_types => event_types,
		:reservable_tools => reservable_tools,
		:tools => tools
	}
end

post '/admin/events/presets/create/?' do
	preset = PresetEvents.new
	name = params[:name]
	description = params[:description]
	type = params[:type]
	area = params[:area]
	max_signups = params[:max_signups]
	duration = params[:duration]

	if name.blank? || description.blank? || type.to_i == 0 || duration.to_i == 0
		flash(:error, 'Preset Event Creation Failed', "Please fill out all required fields.")
		redirect back
	else
		begin
			if !params.checked?('limit_signups')
				max_signups = nil
			end

			preset.event_name = name
			preset.description = description
			preset.event_type_id = type
			preset.max_signups = max_signups
			preset.duration = duration
			preset.area = area
			preset.save

	

			# tie the authorization tools that are checked to the preset event
			params.each do |key, value|
				if key.start_with?('tool_') && value == 'on'
					id = key.split('tool_')[1].to_i
					PresetEventsHasResource.create(
						:preset_events_id => preset.id,
						:resources_id => id
					)
				end
			end

			
			# tie the reservation tools that are checked to the preset event
			params.each do |key, value|
				if key.start_with?('reservation_tool_') && value == 'on'
					id = key.split('reservation_tool_')[1].to_i
					PresetEventsHasResourceReservation.create(
						:preset_events_id => preset.id,
						:resource_id => id
					)
				end
			end
			

			# notify that it worked
			flash(:success, 'Preset Event Created', "Your preset event #{preset.event_name} has been created.")
			redirect '/admin/events/presets'
		rescue => exception
			flash(:error, 'Preset Event Creation Failed', exception.message)
			redirect back
		end
	end
end

get '/admin/events/presets/:preset_id/edit/?' do
	@breadcrumbs << {:text => 'Manage Event Presets', :href => '/admin/events/presets/'}  << {text: 'Edit Preset Event'}
	event_types = EventType.where(:service_space_id => SS_ID).all
	preset = PresetEvents.find_by(:id => params[:preset_id])
	if preset.nil?
		# that preset does not exist
		flash(:danger, 'Not Found', 'That preset event does not exist')
		redirect '/admin/events/presets'
	end

	tools = Resource.where(:service_space_id => SS_ID).order(:name).all.to_a
	tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	
	reservable_tools = Resource.where(:service_space_id => SS_ID, :is_reservable => true).order(:name => :asc).all.to_a
	reservable_tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	
	erb :'admin/new_preset_event', :layout => :fixed_61, :locals => {
		:preset_event => preset,
		:event_types => event_types,
		:reservable_tools => reservable_tools,
		:tools => tools
	}
end

post '/admin/events/presets/:preset_id/edit/?' do
	name = params[:name]
	description = params[:description]
	type = params[:type]
	limit_signups = params[:limit_signups]
	max_signups = params[:max_signups]
	duration = params[:duration]
	area = params[:area]

	preset = PresetEvents.find_by(:id => params[:preset_id])

	# make sure preset exists
	if preset.nil?
		flash(:danger, 'Not Found', 'That preset event does not exist')
		redirect '/admin/events/presets'
	end

	# make sure all required fields are supplied
	if name.blank? || description.blank? || type.to_i == 0 || duration.to_i == 0
		flash(:error, 'Preset Event Update Failed', "Please fill out all required fields.")
		redirect back
	else
		# all required information is present so update the preset
		if !params.checked?('limit_signups')
			max_signups = nil
		end

		begin
			preset.update(event_name: name, description: description, event_type_id: type, max_signups: max_signups, duration: duration, area: area)
		
			# check for removed tools
			preset.get_resource_ids.each do |resource_id|
				unless params.has_key?("tool_#{resource_id}") && params["tool_#{resource_id}"] == 'on'
					PresetEventsHasResource.where(:preset_events_id => preset.id, :resources_id => resource_id).delete_all
				end
			end
		
			# add new tools that are checked
			params.each do |key, value|
				if key.start_with?('tool_') && value == 'on'
					id = key.split('tool_')[1].to_i
					# check if the preset event already has this tool and if not then add it
					unless preset.get_resource_ids.include?(id)
						PresetEventsHasResource.create(
							:preset_events_id => preset.id,
							:resources_id => id
						)
					end
				end
			end

			delete_old_reservations = PresetEventsHasResourceReservation.where(preset_events_id: preset.id).all
    		delete_old_reservations.destroy_all

			
			# add the updated reservation tools that are checked when editing the preset event
			params.each do |key, value|
				if key.start_with?('reservation_tool_') && value == 'on'
					id = key.split('reservation_tool_')[1].to_i
					PresetEventsHasResourceReservation.create(
						:preset_events_id => preset.id,
						:resource_id => id
					)
				end
			end
			

			# notify that it worked
			flash(:success, 'Preset Event Updated', "Your preset event #{preset.event_name} has been updated.")
			redirect '/admin/events/presets'
		rescue => exception
			flash(:error, 'Preset Event Update Failed', exception.message)
			redirect back
		end
	end
end

post '/admin/events/presets/:preset_id/delete/?' do
	preset = PresetEvents.find_by(:id => params[:preset_id])
	if preset.nil?
		# that preset does not exist
		flash(:danger, 'Not Found', 'That preset event does not exist')
		redirect '/admin/events/presets'
	end
	
	delete_reservations = PresetEventsHasResourceReservation.where(preset_events_id: preset.id).all
    delete_reservations.destroy_all

	begin
		preset.get_resource_ids.each do |resource_id|
			PresetEventsHasResource.where(:preset_events_id => preset.id, :resources_id => resource_id).delete_all
		end
		preset.destroy
		flash(:success, 'Preset Event Deleted', "Your preset event #{preset.event_name} has been deleted.")
		redirect '/admin/events/presets'
	rescue => exception
		flash(:error, 'Preset Event Deletion Failed', exception.message)
		redirect back
	end
end