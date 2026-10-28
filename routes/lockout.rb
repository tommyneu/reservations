require 'models/resource'
require 'models/lockout'

get '/lockout/' do
    require_login
    @breadcrumbs << {:text => 'Lockout'}

    workshop_category = params[:workshop_category]

    tools = Resource.where(:service_space_id => SS_ID).all.to_a
    unless workshop_category.nil? || workshop_category.length == 0
			tools = Resource.where(:service_space_id => SS_ID).where(:category_id => workshop_category).all.to_a
		end

    tools.sort_by! do |tool|
        [
            tool.category_name.to_s.downcase,
            tool.name.to_s.downcase,
            tool.model.to_s.downcase
        ]
    end

    erb :'lockout', :layout => :fixed_61, :locals => {
        :workshop_category => workshop_category,
        :tools => tools
    }
end

get '/lockout/:resource_id/create/?' do
	require_login
	@breadcrumbs << {:text => 'Lockout', :href => '/lockout/'} << {:text => 'Lockout Tool'}

	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect back
	end

	# only admins can schedule lockouts on currently locked out resources
	if tool.is_locked_out? && !has_permission?(Permission::MANAGE_LOCKOUT)
		flash(:alert, 'Tool Locked Out', 'That tool is already locked out.')
		redirect back
	end

	# 24 hour availability in 30 min increments
	available_start_times = []
	available_start_times << -1
	start = 0
	while start + 30 <= 1440
		available_start_times << start
		start += 30
	end

	lockouts = Lockout.where(:resource_id => tool.id).order('started_on DESC')
	scheduled_lockouts = lockouts.select do |lockout|
		lockout.started_on > Time.now
	end.sort_by { |lockout| lockout.started_on }.reverse

	erb :'lockout_resource', :layout => :fixed_61, :locals => {
		:tool => tool,
		:available_start_times => available_start_times,
		:scheduled_lockouts => scheduled_lockouts
	}
end

post '/lockout/:resource_id/create/?' do
	require_login
	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil? || tool.service_space_id != 8
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/admin/tools/'
	end
	if tool.is_locked_out? && !has_permission?(Permission::MANAGE_LOCKOUT)
		flash(:alert, 'Tool Locked Out', 'That tool is already locked out.')
		redirect back
	end

	unless params[:start_date].to_s.strip.empty?
		if params[:start_minutes] == "empty"
			params[:start_minutes] = 0
		end
		start_hour = (params[:start_minutes].to_i / 60).floor
		start_am_pm = start_hour >= 12 ? 'pm' : 'am'
		start_hour = start_hour % 12
		start_hour += 12 if start_hour == 0
		start_minutes = params[:start_minutes].to_i % 60

		start_time = calculate_time(params[:start_date], start_hour, start_minutes, start_am_pm)
	end

	unless params[:end_date].to_s.strip.empty?
		if params[:end_minutes] == "empty"
			params[:end_minutes] = 0
		end
		end_hour = (params[:end_minutes].to_i / 60).floor
		end_am_pm = end_hour >= 12 ? 'pm' : 'am'
		end_hour = end_hour % 12
		end_hour += 12 if end_hour == 0
		end_minutes = params[:end_minutes].to_i % 60

		end_time = calculate_time(params[:end_date], end_hour, end_minutes, end_am_pm)
	end

	if tool.is_locked_out? && (start_time.nil? || end_time.nil?)
		flash(:alert, 'Invalid Time', 'You must specify a valid start and end time to schedule a lockout.')
		redirect back
	end

	if !start_time.nil? && !end_time.nil? && start_time >= end_time
		flash(:alert, 'Invalid Time', 'The start time must be before the end time.')
		redirect back
	end

	params[:start_time] = start_time
	params[:end_time] = end_time

	lockout = Lockout.new
	lockout.set_data(params)
	lockout.email_lockout_affected_users(Time.now.in_time_zone, Time.now.in_time_zone.midnight + 2.day)
	flash(:success, 'Lockout Created', 'The lockout has been created.')
	redirect '/lockout/'
end

get '/lockout/:resource_id/edit/:lockout_id/?' do
	require_login
	@breadcrumbs << {:text => 'Lockout', :href => '/lockout/'} << {:text => 'Edit Lockout'}
	unless has_permission?(Permission::MANAGE_LOCKOUT)
		redirect back
	end

	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect back
	end

	lockout = Lockout.find_by(:id => params[:lockout_id])
	if lockout.nil?
		flash(:alert, 'Not Found', 'That lockout does not exist.')
		redirect back
	end

	# 24 hour availability in 30 min increments
	available_start_times = []
	available_start_times << -1
	start = 0
	while start + 30 <= 1440
		available_start_times << start
		start += 30
	end

	lockouts = Lockout.where(:resource_id => tool.id).order('started_on DESC')
	scheduled_lockouts = lockouts.select do |lockout|
		lockout.started_on > Time.now && lockout.id != params[:lockout_id].to_i
	end.sort_by { |lockout| lockout.started_on }.reverse

	fromHistory = false
	if params[:fromHistory]
		fromHistory = true
	end

	erb :'edit_lockout', :layout => :fixed_61, :locals => {
		:tool => tool,
		:lockout => lockout,
		:available_start_times => available_start_times,
		:scheduled_lockouts => scheduled_lockouts,
		:fromHistory => fromHistory
	}
end

post '/lockout/:resource_id/edit/:lockout_id/?' do
	require_login
	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil? || tool.service_space_id != 8
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect back
	end
	lockout = Lockout.find_by(:id => params[:lockout_id])
	if lockout.nil?
		flash(:alert, 'Not Found', 'That lockout does not exist.')
		redirect back
	end

	unless params[:start_date].to_s.strip.empty? || params[:start_minutes] == "empty"
		start_hour = (params[:start_minutes].to_i / 60).floor
		start_am_pm = start_hour >= 12 ? 'pm' : 'am'
		start_hour = start_hour % 12
		start_hour += 12 if start_hour == 0
		start_minutes = params[:start_minutes].to_i % 60

		start_time = calculate_time(params[:start_date], start_hour, start_minutes, start_am_pm)
	end

	unless params[:end_date].to_s.strip.empty?
		if params[:end_minutes] == "empty"
			params[:end_minutes] = 0
		end
		end_hour = (params[:end_minutes].to_i / 60).floor
		end_am_pm = end_hour >= 12 ? 'pm' : 'am'
		end_hour = end_hour % 12
		end_hour += 12 if end_hour == 0
		end_minutes = params[:end_minutes].to_i % 60

		end_time = calculate_time(params[:end_date], end_hour, end_minutes, end_am_pm)
	end
	if !start_time.nil? && !end_time.nil? && start_time >= end_time
		flash(:alert, 'Invalid Time', 'The start time must be before the end time.')
		redirect back
	end

	# if they removed the start time or end time, use the original start time
	params[:start_time] = start_time.nil? ? lockout.started_on : start_time
	params[:end_time] = end_time.nil? ? lockout.released_on : end_time

	# only email if the time range has been changed
	if params[:start_time] != lockout.started_on || params[:end_time] != lockout.released_on
			lockout.set_data(params)
			lockout.email_edit_lockout_affected_users(start_time, end_time)
	else
		lockout.set_data(params)
	end

	flash(:success, 'Lockout Updated', 'The lockout has been updated.')
	redirect '/lockout/' + params[:resource_id] + '/view/'
end

get '/lockout/:resource_id/view/?' do
	require_login
	@breadcrumbs << {:text => 'Lockout', :href => '/lockout/'} << {:text => 'View LOTO Details'}
	unless has_permission?(Permission::MANAGE_LOCKOUT)
		redirect back
	end

	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect back
	end

	lockouts = Lockout.where(:resource_id => tool.id).order('started_on DESC')

	active_lockouts = lockouts.select do |lockout|
		lockout.started_on <= Time.now && (lockout.released_on.nil? || lockout.released_on >= Time.now)
	end
	scheduled_lockouts = lockouts.select do |lockout|
		lockout.started_on > Time.now
	end.sort_by { |lockout| lockout.started_on }.reverse

	lockout_history = lockouts.select do |lockout|
		lockout.started_on < Time.now && !lockout.released_on.nil? && lockout.released_on < Time.now
	end.sort_by { |lockout| lockout.released_on }.reverse

	erb :'view_resource_lockout', :layout => :fixed_61, :locals => {
		:tool => tool,
		:active_lockouts => active_lockouts,
		:scheduled_lockouts => scheduled_lockouts,
		:lockout_history => lockout_history,
	}
end

post '/lockout/:resource_id/release_all/?' do
	require_login
	tool = Resource.find_by(:id => params[:resource_id], :service_space_id => SS_ID)
	if tool.nil?
		flash(:alert, 'Not Found', 'That tool does not exist.')
		redirect '/admin/tools/'
	end
	lockouts = Lockout.where(:resource_id => tool.id).order('started_on DESC')
	if lockouts.nil?
		flash(:alert, 'Not Found', 'That tool is not locked out.')
		redirect '/admin/tools/'
	end
	params[:user_id] = @user.id;

	lockouts.each do |lockout|
		if lockout.started_on <= Time.now && (lockout.released_on.nil? || lockout.released_on >= Time.now)
			if lockout.released_on.nil?
				lockout.email_release_affected_users()
			end
			lockout.release(params)
		end
	end
	flash(:success, 'Lockout Released', 'The lockout has been released.')
	redirect back
end

post '/lockout/:resource_id/release/:lockout_id/' do
	require_login

	lockout = Lockout.find_by(:id => params[:lockout_id])
	if lockout.nil?
		flash(:alert, 'Not Found', 'That lockout does not exist.')
		redirect '/lockout/' + params[:resource_id] + '/view/'
	end

	params[:user_id] = @user.id;

	lockout.email_release_affected_users()
	lockout.release(params)
	flash(:success, 'Lockout Released', 'The lockout has been released.')
	redirect '/lockout/' + params[:resource_id] + '/view/'
end

post '/lockout/:resource_id/delete/:lockout_id/' do
	require_login
	unless has_permission?(Permission::MANAGE_LOCKOUT)
		redirect back
	end

	lockout = Lockout.find_by(:id => params[:lockout_id])
	if lockout.nil?
		flash(:alert, 'Not Found', 'That lockout does not exist.')
		redirect '/lockout/' + params[:resource_id] + '/view/'
	end

	lockout.destroy
	flash(:success, 'Lockout Deleted', 'The lockout has been deleted.')
	redirect '/lockout/' + params[:resource_id] + '/view/'
end