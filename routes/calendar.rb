require 'models/event'

get '/calendar/?' do
	@breadcrumbs << {:text => 'Calendar'}

	# get all events for this week
	date = params[:date].nil? ? Time.now : Time.parse(params[:date])
	events = Event.includes(:event_type).where(:service_space_id => SS_ID).in_week(date).all
	sunday = date.in_time_zone.week_start

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

	erb :calendar, :layout => :fixed_61, :locals => {
		:date => date,
		:sunday => sunday,
		:events => events,
		:week_hours => week_hours
	}
end
