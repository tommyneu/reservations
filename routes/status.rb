require 'models/resource'
require 'models/reservation'
require 'models/event'
require 'models/event_type'
require 'models/event_signup'
require 'models/space_hour'
require 'erb'
require 'models/lockout'
require 'models/touch_point_log'


get '/status_page/?' do
  @breadcrumbs << { text: 'Status Page' }

  SS_ID = ServiceSpace.where(id: CONFIG['app']['service_space_id']).first.id

    lockouts = Lockout
      .where('started_on <= ?', Time.now).where('released_on IS NULL OR released_on > ?', Time.now).includes(:resource)
    lockout_count = lockouts.select(:resource_id).distinct.count
    upcoming_lockouts = Lockout.where('started_on BETWEEN ? AND ?', Time.now, Time.now + 7.days).includes(:resource)
    reservations = Reservation.joins(:resource).where("resource.service_space_id" => SS_ID).select(:id, :start_time, :end_time).where.not(start_time: nil, end_time: nil)

    # Retrieve a list events ID's of events with the Design Hub Orientation Event Type
    orientation_ids = Event.where(event_type_id: 12).pluck(:id)
    # Retrieve a list of event signups based on the orientation ID's (ActiveRecord handles multiple inputs for SQL search)
    orientation_signups = EventSignup.where(event_id: orientation_ids)
    # Get the number of people that haven't attended Orientation from the previous query
    orientation_potentials = orientation_signups.where(attended: false).count

    # Get timeless events and their unattended signups count
    timeless_events = Event.where(start_time: nil, service_space_id: 8).where.not(event_type_id: 12).map do |event|
        {
        title: event.title,
        potential_walkins: EventSignup.where(event_id: event.id, attended: false).count
        }
    end
    
    # Forecasting Logic
    forecasts_by_day = {}
    changes_by_day = {}
    
    (0..6).each do |i|
        day_name = (Date.today + i).strftime('%a')
        dates = [21, 14, 7].map { |days_ago| Date.today - days_ago + i }
    
        touchdata = dates.map do |target_date|
        TouchPointLog
            .where("DATE(created_on) = ?", target_date)
            .order(:created_on)
            .first
        end.compact
    
        if touchdata.size == 3
        x_values = [3, 2, 1]
        y_values = touchdata.map(&:touch_point_count)
    
        x_mean = x_values.sum.to_f / x_values.size
        y_mean = y_values.sum.to_f / y_values.size
    
        numerator = x_values.zip(y_values).map { |x, y| (x - x_mean) * (y - y_mean) }.sum
        denominator = x_values.map { |x| (x - x_mean)**2 }.sum
    
        slope = numerator / denominator
        intercept = y_mean - slope * x_mean # we only need intercept since the full equ is forecast = (slope * x_forecast) + intercept but x_forecast = 0
        forecast = intercept.round
    
        forecasts_by_day[day_name] = forecast
        changes_by_day[day_name] = forecast - y_values.last
        else
        forecasts_by_day[day_name] = nil
        changes_by_day[day_name] = nil
        end
    end

    # Round current time down to nearest 30-minute mark
    chart_start = Time.at((Time.now.to_i / 1800) * 1800)
    chart_end = chart_start + 24.hours

    # Create bins for 30-min intervals over 24 hours 
    bins = {}
    current = chart_start
    while current < chart_end
      bins[current] = 0
      current += 30.minutes
    end


    reservations.each do |res|
      current_time = res.start_time

      while current_time < res.end_time
        interval = Time.at(((current_time + 5.hours).to_i / 1800) * 1800)
        if interval >= chart_start && interval < chart_end
          bins[interval] += 1
        end
        current_time += 30.minutes
      end
    end

	erb :'/engineering_design_hub/status_page', :layout => :fixed_61, :locals => {
        :lockout_count => lockout_count,
        :lockouts => lockouts,
        :orientation_potentials => orientation_potentials,
        :upcoming_lockouts => upcoming_lockouts,
        :reservations => reservations,
        :timeless_events => timeless_events,
        :forecasts_by_day => forecasts_by_day,
        :changes_by_day => changes_by_day,
        :bins => bins,
        :chart_start => chart_start
    }
end
