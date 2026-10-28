require 'json'
require 'models/space_hour'
require 'models/permission'

before '/admin/hours*' do
	unless has_permission?(Permission::MANAGE_SPACE_HOURS)
		raise Sinatra::NotFound
	end
end

get '/admin/hours/?' do
	session.delete(:space_hour)
	session.delete(:hours)

	# get the hours for this week to show
	date = params[:date].nil? ? Time.now.in_time_zone.midnight : Time.parse(params[:date]).in_time_zone.midnight
	sunday = date.week_start

	hours = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date < ?', (sunday+1.week+1.hour).midnight.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.order(:day_of_week, :effective_date => :desc, :id => :desc).all.to_a

	hours_days = hours.group_by do |space_hour|
		space_hour.day_of_week
	end

	week_hours = {}
	hours_days.each do |number_of_days, array|
		this_day = (sunday + number_of_days.days + 1.hour).midnight

		# find the correct hour record to use for this day
		array.each do |space_hour|
			if space_hour.effective_date.in_time_zone.midnight == this_day.in_time_zone.midnight || (!space_hour.one_off && space_hour.effective_date.in_time_zone.midnight <= this_day.in_time_zone.midnight)
				week_hours[number_of_days] = space_hour
				break
			end
		end
	end

	upcoming_hours = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date >= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.where('effective_date <= ?', (date+365.days).utc.strftime('%Y-%m-%d %H:%M:%S'))
		.order(:effective_date).all

	erb :'admin/hours', :layout => :fixed_61, :locals => {
		:weeks_hours => week_hours,
		:upcoming_hours => upcoming_hours,
		:sunday => sunday,
		:date => date
	}
end

get '/admin/hours/create/?' do
	# show a form for setting a weekly schedule for a day or a one-off
	erb :'admin/new_hours', :layout => :fixed_61, :locals => {
		:space_hour => SpaceHour.new,
		:hours => session.delete(:hours)
	}
end

get '/admin/hours/:hour_id/edit/?' do
	space_hour = SpaceHour.where(:service_space_id => SS_ID, :id => params[:hour_id]).first
	if space_hour.nil?
		flash :error, 'Not Found', 'Those hours were not found.'
		redirect '/admin/hours/'
	end

	# show form for editing
	erb :'admin/new_hours', :layout => :fixed_61, :locals => {
		:space_hour => session.delete(:space_hour) || space_hour,
		:hours => session.delete(:hours) || space_hour.hours
	}
end

post '/admin/hours/:hour_id/edit/?' do
	space_hour = SpaceHour.where(:service_space_id => SS_ID, :id => params[:hour_id]).first
	if space_hour.nil?
		flash :error, 'Not Found', 'Those hours were not found.'
		redirect '/admin/hours/'
	end

	# basically put the inputted data into the database
	eff_date = calculate_time(params[:effective_date], 0, 0, 'am').in_time_zone.midnight
	day_of_week = params[:day_of_week] == 'one_off' ? eff_date.wday : params[:day_of_week]

	space_hour.day_of_week = day_of_week
	space_hour.effective_date = eff_date
	space_hour.one_off = params[:day_of_week] == 'one_off'

	# Sort records by start
	hours_params = JSON.parse(params[:hours])
	hours_params.map! do |record|
		start_time = calculate_time(eff_date.strftime('%Y-%m-%d'), record['start_hour'], record['start_minute'], record['start_am_pm'])
		end_time = calculate_time(eff_date.strftime('%Y-%m-%d'), record['end_hour'], record['end_minute'], record['end_am_pm'])
		{
			:status => record['status'],
			:start => start_time.hour * 60 + start_time.min,
			:end => end_time.hour * 60 + end_time.min
		}
	end.sort! do |a,b|
		a[:start] <=> b[:start]
	end

	hours_params.each do |record|
		if record[:start] > record[:end]
			# error here, this is invalid
			flash :danger, 'Improper Hours', "Your end times must each be after their start time."
			session[:space_hour] = space_hour
			session[:hours] = hours_params
			redirect "/admin/hours/#{space_hour.id}/edit/"
		end
	end

	# check that record starts and ends do not overlap. 
	zones = []
	hours_params.each do |record|
		zones.each do |zone|
			if zone.include?(record[:start]) || zone.include?(record[:end])
				# record starts or ends inside of zone, invalid
				flash :danger, 'Improper Hours', "Your hours for this day must not overlap."
				session[:hours] = hours_params
				session[:space_hour] = space_hour
				redirect "/admin/hours/#{space_hour.id}/edit/"
			elsif zone.min < record[:start] && zone.max > record[:end]
				# new record covers entire zone, invalid
				flash :danger, 'Improper Hours', "Your hours for this day must not overlap."
				session[:hours] = hours_params
				session[:space_hour] = space_hour
				redirect "/admin/hours/#{space_hour.id}/edit/"
			end
		end
		# add this record to the zones
		zones << (record[:start]..record[:end])
	end

	space_hour.update({
		:service_space_id => SS_ID,
		:day_of_week => day_of_week,
		:effective_date => eff_date,
		:one_off => params[:day_of_week] == 'one_off',
		:hours => hours_params
	})

	flash :success, 'Hours Saved', "Your hours effective #{eff_date.strftime('%B %d, %Y')} have been saved."
	session.delete :hours
	redirect '/admin/hours/'
end

post '/admin/hours/create/?' do
	# basically put the inputted data into the database
	eff_date = calculate_time(params[:effective_date], 0, 0, 'am').in_time_zone.midnight
	day_of_week = params[:day_of_week] == 'one_off' ? eff_date.wday : params[:day_of_week]

	# Sort records by start
	hours_params = JSON.parse(params[:hours])
	hours_params.map! do |record|
		start_time = calculate_time(eff_date.strftime('%Y-%m-%d'), record['start_hour'], record['start_minute'], record['start_am_pm'])
		end_time = calculate_time(eff_date.strftime('%Y-%m-%d'), record['end_hour'], record['end_minute'], record['end_am_pm'])
		{
			:status => record['status'],
			:start => start_time.hour * 60 + start_time.min,
			:end => end_time.hour * 60 + end_time.min
		}
	end.sort! do |a,b|
		a[:start] <=> b[:start]
	end

	hours_params.each do |record|
		if record[:start] > record[:end]
			# error here, this is invalid
			flash :danger, 'Improper Hours', "Your end times must each be after their start time."
			session[:hours] = hours_params
			redirect '/admin/hours/create/'
		end
	end

	# check that record starts and ends do not overlap. 
	zones = []
	hours_params.each do |record|
		zones.each do |zone|
			if zone.include?(record[:start]) || zone.include?(record[:end])
				# record starts or ends inside of zone, invalid
				flash :danger, 'Improper Hours', "Your hours for this day must not overlap."
				session[:hours] = hours_params
				redirect '/admin/hours/create/'
			elsif zone.min < record[:start] && zone.max > record[:end]
				# new record covers entire zone, invalid
				flash :danger, 'Improper Hours', "Your hours for this day must not overlap."
				session[:hours] = hours_params
				redirect '/admin/hours/create/'
			end
		end
		# add this record to the zones
		zones << (record[:start]..record[:end])
	end

	SpaceHour.create({
		:service_space_id => SS_ID,
		:day_of_week => day_of_week,
		:effective_date => eff_date,
		:one_off => params[:day_of_week] == 'one_off',
		:hours => hours_params
	})

	flash :success, 'Hours Saved', "Your hours effective #{eff_date.strftime('%B %d, %Y')} have been saved."
	session.delete :hours
	redirect '/admin/hours/'
end

post '/admin/hours/:hour_id/delete/?' do
	space_hour = SpaceHour.find_by(:id => params[:hour_id], :service_space_id => SS_ID)
	if space_hour.nil?
		# that space hour does not exist
		flash(:danger, 'Not Found', 'That hours record does not exist.')
		redirect '/admin/hours/'
	end

	space_hour.delete

	flash(:success, 'Hours Change Deleted', "This hours change has been removed.")
	redirect '/admin/hours/'
end