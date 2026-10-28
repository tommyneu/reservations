require 'models/resource'
require 'models/reservation'
require 'models/event'
require 'models/event_type'
require 'models/event_signup'
require 'models/space_hour'
require 'erb'

get '/tools/?' do
	@breadcrumbs << {:text => 'Tools'}
	require_login

	workshop_category = params[:workshop_category]

	# show tools that the user is authorized to use, as well as all those that do not require authorization
	tools = Resource.where(:service_space_id => SS_ID).all.to_a

	# Redefine the tools variable if there is a workshop category filter applied
	unless workshop_category.nil? || workshop_category.length == 0
		tools = Resource.where(:service_space_id => SS_ID).where(:category_id => workshop_category).all.to_a
	end

	tools.reject! {|tool| tool.needs_authorization && !@user.authorized_resource_ids.include?(tool.id)}

	if SS_ID == 8
		tools.reject! {|tool| tool.is_manually_locked_out?}
	end
	
	tools.sort_by! do |tool|
		[
			tool.category_name.to_s.downcase,
			tool.name.to_s.downcase,
			tool.model.to_s.downcase
		]
	end
	

	erb :tools, :layout => :fixed_61, :locals => {
		:workshop_category => workshop_category,
		:available_tools => tools
	}
end

get '/tools/trainings/?' do
	@breadcrumbs << {:text => 'Tools', :href => '/tools/'} << {:text => 'Upcoming Trainings'}
	require_login

	WHERE_CLAUSE = 'start_time >= ?'

	events_advanced = nil
	events_creation = nil
	events_general = nil

	machine_training_id = EventType.find_by(:description => 'Machine Training', :service_space_id => SS_ID).id
	events = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => machine_training_id).
		where(WHERE_CLAUSE, Time.now).order(:start_time => :asc).all

	if SS_ID == 1
		workshop_id = EventType.find_by(:description => 'Advanced Skill-Based Workshop', :service_space_id => SS_ID).id
		events_advanced = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
			where(WHERE_CLAUSE, Time.now).order(:start_time => :asc).all

		workshop_id = EventType.find_by(:description => 'Creation Workshop', :service_space_id => SS_ID).id
		events_creation = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
			where(WHERE_CLAUSE, Time.now).order(:start_time => :asc).all

		workshop_id = EventType.find_by(:description => 'General Workshop', :service_space_id => SS_ID).id
		events_general = Event.includes(:event_signups).where(:service_space_id => SS_ID, :event_type_id => workshop_id).
			where(WHERE_CLAUSE, Time.now).order(:start_time => :asc).all
	end


	erb :trainings, :layout => :fixed_61, :locals => {
		:events => events,
		:events_advanced => events_advanced,
		:events_creation => events_creation,
		:events_general => events_general
	}
end

post '/tools/trainings/sign_up/:event_id/?' do
	require_login

	# check that is a valid event
	machine_training_id = EventType.find_by(:description => 'Machine Training', :service_space_id => SS_ID).id
	event = Event.find_by(:service_space_id => SS_ID, :event_type_id => machine_training_id, :id => params[:event_id])

	if event.nil?
		# that event does not exist
		flash(:danger, 'Not Found', 'That event does not exist')
		redirect '/tools/trainings/'
	end

	if !event.max_signups.nil? && event.signups.count >= event.max_signups
		# that event is full
		flash(:danger, 'Event Full', 'Sorry, that event is full.')
		redirect '/tools/trainings/'
	end


	if event.event_code.present? && params[:event_code].blank?
		# a code is required to sign up
		flash(:danger, 'Code Required', 'Sorry, a code is required to signup for this event. You have not been signed up for this event.')
		redirect '/tools/trainings/'
	elsif !event.event_code.nil? && !params[:event_code].blank?
		unless params[:event_code] == event.event_code
			# incorrect code provided
			flash(:danger, 'Incorrect Code', 'Sorry, the code you entered is incorrect. You have not been signed up for this event.')
			redirect '/tools/trainings/'
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
		template_path = "#{ROOT}/views/innovationstudio/email_templates/training_signup_email.erb"
		if SS_ID == 8
			template_path = "#{ROOT}/views/engineering_design_hub/email_templates/training_signup_email.erb"
		end
		template = File.read(template_path)
		body = ERB.new(template).result(binding)
		
		Emailer.mail(@user.email, "#{CONFIG['app']['title']} - #{event.title}", body)
	end

	# flash a message that this works
	flash(:success, "You're signed up!", "Thanks for signing up! Don't forget, #{event.title} is #{event.start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}.")
	redirect '/tools/trainings/'
end

get '/tools/:resource_id/reserve/?' do
	@breadcrumbs << {:text => 'Tools', :href => '/tools/'} << {:text => 'Reserve'}
	require_login

	# check that the user has authorization to reserve this tool, if tool requires auth
	tool = Resource.find_by(:service_space_id => SS_ID, :id => params[:resource_id])
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/tools/'
	end

	if tool.is_manually_locked_out?
		flash(:alert, 'Locked Out', 'Sorry, this tool is currently locked out for maintenance.')
		redirect '/tools/'
	end

	unless !tool.needs_authorization || @user.authorized_resource_ids.include?(tool.id)
		flash(:alert, 'Not Authorized', 'Sorry, you have not yet been authorized to reserve time on this machine.')
		redirect '/tools/'
	end

	date = params[:date].nil? ? Time.now.midnight.in_time_zone : Time.parse(params[:date]).midnight.in_time_zone
	# get the studio's hours for this day
	# is there a one_off
	space_hour = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date = ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.where(:day_of_week => date.wday).where(:one_off => true).first
	if space_hour.nil?
		space_hour = SpaceHour.where(:service_space_id => SS_ID)
			.where('effective_date <= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
			.where(:day_of_week => date.wday).where(:one_off => false)
			.order(:effective_date => :desc, :id => :desc).first
	end

	available_start_times = []
	# calculate the available start times for reservation
	if space_hour.nil? || (tool.is_24_hour && SS_ID == 8)
		start = 0
		while start + (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15) <= 1440
			available_start_times << start
			start += (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15)
		end
	else
		space_hour.hours.sort{|x,y| x[:start] <=> y[:start]}.each do |record|
			if record[:status] == 'open'
				start = record[:start]
				while start + (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15) <= record[:end]
					available_start_times << start
					start += (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15)
				end
			end
		end
	end

	# filter out times when tool is reserved
	reservations = Reservation.includes(:event).where(:resource_id => tool.id).in_day(date).all
    unavailable_start_times = []
    available_start_times.each do |available_start_time|
				if tool.is_24_hour && SS_ID == 8
						date_start = (date.midnight) # 12:00 am
						date_end = (date.end_of_day) # 11:59 pm
				else
						date_start = (date.midnight + 21600) # 06:00 am
						date_end = (date.end_of_day - 1799)  # 11:30 pm
				end
        reservations.each do |res|
            if res.start_time.in_time_zone <= date_start
                start_time = date_start
            else
                start_time = res.start_time.in_time_zone
            end

            if res.end_time.in_time_zone >= date_end
                end_time = date_end
            else
                end_time = res.end_time.in_time_zone
            end
            if available_start_time >= start_time.minutes_after_midnight && available_start_time < end_time.minutes_after_midnight
               unavailable_start_times << available_start_time
               break
            end
        end
    end
    available_start_times = available_start_times - unavailable_start_times

		# filter out times when a tool is scheduled for lockout
		if SS_ID == 8
			lockouts = Lockout.where(:resource_id => tool.id).in_day(date).all
			unavailable_start_times = []
			available_start_times.each do |available_start_time|
				if tool.is_24_hour && SS_ID == 8
						date_start = (date.midnight) # 12:00 am
						date_end = (date.end_of_day) # 11:59 pm
				else
						date_start = (date.midnight + 21600) # 06:00 am
						date_end = (date.end_of_day - 1799)  # 11:30 pm
				end
				lockouts.each do |lockout|
					if lockout.started_on.in_time_zone <= date_start
							start_time = date_start
					else
							start_time = lockout.started_on.in_time_zone
					end

					if lockout.released_on.nil?
						end_time = date_end
					elsif lockout.released_on.in_time_zone >= date_end
							end_time = date_end
					else
							end_time = lockout.released_on.in_time_zone
					end
					if available_start_time >= start_time.minutes_after_midnight && available_start_time < end_time.minutes_after_midnight
						unavailable_start_times << available_start_time
						break
					end
				end
			end
			available_start_times = available_start_times - unavailable_start_times
		else
			lockouts = []
		end

	erb :reserve, :layout => :fixed_61, :locals => {
		:tool => tool,
		:reservations => reservations,
		:lockouts => lockouts,
		:available_start_times => available_start_times,
		:space_hour => space_hour,
		:day => date,
		:reservation => nil
	}
end

get '/tools/:resource_id/edit_reservation/:reservation_id/?' do
	@breadcrumbs << {:text => 'Tools', :href => '/tools/'} << {:text => 'Edit Reservation'}
	require_login

	# check that the user has authorization to reserve this tool, if tool requires auth
	tool = Resource.find_by(:service_space_id => SS_ID, :id => params[:resource_id])
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/tools/'
	end

	unless !tool.needs_authorization || @user.authorized_resource_ids.include?(tool.id)
		flash(:alert, 'Not Authorized', 'Sorry, you have not yet been authorized to reserve time on this machine.')
		redirect '/tools/'
	end

	# check that this reservation exists
	reservation = Reservation.find(params[:reservation_id])
	if reservation.nil?
		flash(:alert, 'Not Found', 'That reservation does not exist.')
		redirect back
	end

	date = params[:date].nil? ? reservation.start_time.in_time_zone.midnight : Time.parse(params[:date]).midnight.in_time_zone
	# get the studio's hours for this day
	# is there a one_off
	space_hour = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date = ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.where(:day_of_week => date.wday).where(:one_off => true).first
	if space_hour.nil?
		space_hour = SpaceHour.where(:service_space_id => SS_ID)
			.where('effective_date <= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
			.where(:day_of_week => date.wday).where(:one_off => false)
			.order(:effective_date => :desc, :id => :desc).first
	end

	available_start_times = []
	# calculate the available start times for reservation
	if space_hour.nil? || (tool.is_24_hour && SS_ID == 8)
		start = 0
		while start + (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15) <= 1440
			available_start_times << start
			start += (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15)
		end
	else
		space_hour.hours.sort{|x,y| x[:start] <=> y[:start]}.each do |record|
			if record[:status] == 'open'
				start = record[:start]
				while start + (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15) <= record[:end]
					available_start_times << start
					start += (tool.minutes_per_reservation || tool.min_minutes_per_reservation || 15)
				end
			end
		end
	end

	# filter out times when tool is reserved
	reservations = Reservation.includes(:event).where(:resource_id => tool.id).in_day(date).all
    unavailable_start_times = []
	available_start_times.each do |available_start_time|
		if tool.is_24_hour && SS_ID == 8
				date_start = (date.midnight) # 12:00 am
				date_end = (date.end_of_day) # 11:59 pm
		else
				date_start = (date.midnight + 21600) # 06:00 am
				date_end = (date.end_of_day - 1799)  # 11:30 pm
		end
        reservations.each do |res|

            # ignore current reseveration since really available
            next if res.id == reservation.id

            if res.start_time.in_time_zone <= date_start
                start_time = date_start
            else
                start_time = res.start_time.in_time_zone
            end

            if res.end_time.in_time_zone >= date_end
                end_time = date_end
            else
                end_time = res.end_time.in_time_zone
            end

            if available_start_time >= start_time.minutes_after_midnight && available_start_time < end_time.minutes_after_midnight
                unavailable_start_times << available_start_time
                break
            end
        end
    end
    available_start_times = available_start_times - unavailable_start_times

		if SS_ID == 8
			lockouts = Lockout.where(:resource_id => tool.id).in_day(date).all
			unavailable_start_times = []
			available_start_times.each do |available_start_time|
				if tool.is_24_hour && SS_ID == 8
						date_start = (date.midnight) # 12:00 am
						date_end = (date.end_of_day) # 11:59 pm
				else
						date_start = (date.midnight + 21600) # 06:00 am
						date_end = (date.end_of_day - 1799)  # 11:30 pm
				end
				lockouts.each do |lockout|
					if lockout.started_on.in_time_zone <= date_start
							start_time = date_start
					else
							start_time = lockout.started_on.in_time_zone
					end

					if lockout.released_on.nil?
							end_time = date_end
					elsif lockout.released_on.in_time_zone >= date_end
							end_time = date_end
					else
							end_time = lockout.released_on.in_time_zone
					end
					if available_start_time >= start_time.minutes_after_midnight && available_start_time < end_time.minutes_after_midnight
						unavailable_start_times << available_start_time
						break
					end
				end
			end
			available_start_times = available_start_times - unavailable_start_times
		else
			lockouts = []
		end

	erb :reserve, :layout => :fixed_61, :locals => {
		:tool => tool,
		:reservations => reservations,
		:available_start_times => available_start_times,
		:space_hour => space_hour,
		:day => date,
		:lockouts => lockouts,
		:reservation => reservation
	}
end

get '/tools/:resource_id/reservations.json' do
	# check that the tool exists
	tool = Resource.find_by(:service_space_id => SS_ID, :id => params[:resource_id])
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/tools/'
	end

	time = params[:time]
	if time.nil?
		time = Time.now
	else
		time = Time.parse(time)
	end

	Reservation.where(:resource_id => tool.id).in_day(time).all.to_json
end

post '/tools/:resource_id/reserve/?' do
	require_login

	# check that the user has authorization to reserve this tool, if tool requires auth
	tool = Resource.find_by(:service_space_id => SS_ID, :id => params[:resource_id])
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/tools/'
	end

	if params[:start_minutes].nil?
		flash(:alert, 'Please specify a start time', 'Please specify a start time for your reservation.')
		redirect back
	end

    unless @user.meets_resource_reservation_limit?(tool.id)
        flash(:alert, 'Not Authorized', "Sorry, you are at the user reservation limit (#{tool.max_reservations_per_user.to_s}) on this machine.")
        redirect back
    end

	hour = (params[:start_minutes].to_i / 60).floor
	am_pm = hour >= 12 ? 'pm' : 'am'
	hour = hour % 12
	hour += 12 if hour == 0
	minutes = params[:start_minutes].to_i % 60

	start_time = calculate_time(params[:date], hour, minutes, am_pm)
	end_time = start_time + params[:length].to_i.minutes

	date = start_time.midnight
	# validate that the requested time slot falls within the open hours of the day
	# get the studio's hours for this day
	# is there a one_off
	space_hour = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date = ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.where(:day_of_week => date.wday).where(:one_off => true).first
	if space_hour.nil?
		space_hour = SpaceHour.where(:service_space_id => SS_ID)
			.where('effective_date <= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
			.where(:day_of_week => date.wday).where(:one_off => false)
			.order(:effective_date => :desc, :id => :desc).first
	end

	unless space_hour.nil? || (tool.is_24_hour && SS_ID == 8)
		# figure out where the closed sections need to be
        # we can assume that all records in this space_hour are non-intertwined
        closed_start = 0
        closed_end = 0
        starts = space_hour.hours.map{|record| record[:start]}
        ends = space_hour.hours.map{|record| record[:end]}
        closeds = []
        (0..1439).each do |j|
            if starts.include?(j)
                closed_end = j
                closeds << {:status => 'closed', :start => closed_start, :end => closed_end}
                closed_start = 0
                closed_end = 0
            end
            if ends.include?(j)
                closed_start = j
            end
        end 
        closed_end = 1440
        closeds << {:status => 'closed', :start => closed_start, :end => closed_end}

		# for each record, ensure that the time does not overlap if the record is not "open"
		(space_hour.hours + closeds).each do |record|
			if record[:status] != 'open'
				start_time_minutes = 60 * start_time.hour + start_time.min
				end_time_minutes = 60 * end_time.hour + end_time.min
        duration = ((end_time - start_time)/60.0).round
        if (record[:start]+1..record[:end]-1).include?(start_time_minutes) || (tool[:time_slot_type] === 'range' && start_time_minutes < record[:end] && record[:start] < end_time_minutes) || duration > tool.max_minutes_per_reservation
					# there is an overlap, this time is invalid
					flash :alert, 'Invalid Time Slot', 'Sorry, that time slot is invalid for reservations.'
					redirect back
				end
			end
		end
	end
	# if no record studio is open

	# check for possible other reservations during this time period
	other_reservations = Reservation.where(:resource_id => params[:resource_id]).in_day(date).all
	other_reservations.each do |reservation|
		if start_time < reservation.end_time && reservation.start_time < end_time
			flash :alert, "Tool is being used.", "Sorry, that tool is reserved during that time period. Please try another time slot."
			redirect back
		elsif reservation.user_id == @user.id
			flash :alert, "Over Limit", "Sorry, you can only reserve this tool once per day. Please try reserving another time slot on another day."
			redirect back
		end
	end

	Reservation.create(
		:resource_id => tool.id,
		:event_id => nil,
		:start_time => start_time,
		:end_time => end_time,
		:is_training => false,
		:user_id => @user.id
	)

	flash(:success, 'Reservation Created', "You have successfully reserved #{tool.name} for #{params[:length]} minutes on #{start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}")
	redirect '/tools/'
end

post '/tools/:resource_id/edit_reservation/:reservation_id/?' do
	require_login

	# check that the user has authorization to reserve this tool, if tool requires auth
	tool = Resource.find_by(:service_space_id => SS_ID, :id => params[:resource_id])
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/tools/'
	end

	# check that this reservation exists
	reservation = Reservation.find(params[:reservation_id])
	if reservation.nil?
		flash(:alert, 'Not Found', 'That reservation does not exist.')
		redirect back
	end

	hour = (params[:start_minutes].to_i / 60).floor
	am_pm = hour >= 12 ? 'pm' : 'am'
	hour = hour % 12
	hour += 12 if hour == 0
	minutes = params[:start_minutes].to_i % 60

	start_time = calculate_time(params[:date], hour, minutes, am_pm)
	end_time = start_time + params[:length].to_i.minutes

	date = start_time.midnight
	# validate that the requested time slot falls within the open hours of the day
	# get the studio's hours for this day
	# is there a one_off
	space_hour = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date = ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.where(:day_of_week => date.wday).where(:one_off => true).first
	if space_hour.nil?
		space_hour = SpaceHour.where(:service_space_id => SS_ID)
			.where('effective_date <= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
			.where(:day_of_week => date.wday).where(:one_off => false)
			.order(:effective_date => :desc, :id => :desc).first
	end

	unless space_hour.nil? || (tool.is_24_hour && SS_ID == 8)
		# figure out where the closed sections need to be
        # we can assume that all records in this space_hour are non-intertwined
        closed_start = 0
        closed_end = 0
        starts = space_hour.hours.map{|record| record[:start]}
        ends = space_hour.hours.map{|record| record[:end]}
        closeds = []
        (0..1439).each do |j|
            if starts.include?(j)
                closed_end = j
                closeds << {:status => 'closed', :start => closed_start, :end => closed_end}
                closed_start = 0
                closed_end = 0
            end
            if ends.include?(j)
                closed_start = j
            end
        end 
        closed_end = 1440
        closeds << {:status => 'closed', :start => closed_start, :end => closed_end}

		# for each record, ensure that the time does not overlap if the record is not "open"
		(space_hour.hours + closeds).each do |record|
			if record[:status] != 'open'
				start_time_minutes = 60 * start_time.hour + start_time.min
				end_time_minutes = 60 * end_time.hour + end_time.min
        duration = ((end_time - start_time)/60.0).round
        if (record[:start]+1..record[:end]-1).include?(start_time_minutes) || (tool[:time_slot_type] === 'range' && start_time_minutes < record[:end] && record[:start] < end_time_minutes) || duration > tool.max_minutes_per_reservation
					# there is an overlap, this time is invalid
					flash :alert, 'Invalid Time Slot', 'Sorry, that time slot is invalid for reservations.'
					redirect back
				end
			end
		end
	end
	# if no record studio is open

	# check for possible other reservations during this time period
	other_reservations = Reservation.where(:resource_id => params[:resource_id]).where.not(:id => reservation.id).in_day(date).all
	other_reservations.each do |reservation|
		if start_time < reservation.end_time && reservation.start_time < end_time
			flash :alert, "Tool is being used.", "Sorry, that tool is reserved during that time period. Please try another time slot."
			redirect back
		elsif reservation.user_id == @user.id
			flash :alert, "Over Limit", "Sorry, you can only reserve this tool once per day. Please try reserving another time slot on another day."
			redirect back
		end
	end

	reservation.update(
		:start_time => start_time,
		:end_time => end_time
	)

	flash(:success, 'Reservation Updated', "You have successfully updated your reservation for #{tool.name}: it is now for #{params[:length]} minutes at #{start_time.in_time_zone.strftime('%A, %B %d at %l:%M %P')}")
	redirect back
end

post '/tools/:resource_id/cancel/:reservation_id/?' do
	require_login

	# check that the user requesting cancel is the same as the one on the reservation
	reservation = Reservation.find(params[:reservation_id])
	if reservation.nil?
		flash :alert, 'Not Found', 'That reservation was not found.'
		redirect back
	end

	if reservation.user_id != @user.id
		flash :alert, 'Unauthorized', 'That is not your reservation.'
		redirect back
	end

	reservation.delete

	flash :success, 'Reservation Cancelled', 'Your reservation has been removed.'
	redirect back
end


