require 'models/user'
require 'models/event'
require 'models/resource'
require 'models/space_hour'
require 'models/permission'

def calculate_time(date_string, hour, minute, am_pm)
	hour ||= 0
	minute ||= 0
	am_pm ||= 'am'

	hour = hour.to_i % 12
	hour = hour + 12 if am_pm == 'pm'

	date_strings = date_string.split('/')
	date_string = "#{date_strings[2]}-#{date_strings[0]}-#{date_strings[1]}"
	date = Time.parse(date_string)
	Time.new(date.year, date.month, date.day, hour, minute, 0)
end

before '/admin*' do
	raise Sinatra::NotFound unless !@user.nil? && @user.is_admin?
end

get '/admin/?' do
	@breadcrumbs << {:text => 'Admin Home'}
	user_count = User.where(:service_space_id => SS_ID).count
	upcoming_event_count = Event.where(:service_space_id => SS_ID).where('start_time >= ?', Time.now).count
	tool_count = Resource.where(:service_space_id => SS_ID).count

	date = Time.now.midnight
	# get the hours for this day to show
	hours = SpaceHour.where(:service_space_id => SS_ID)
		.where('effective_date <= ?', date.utc.strftime('%Y-%m-%d %H:%M:%S'))
		.order(:effective_date => :desc, :id => :desc).all.to_a

	correct_hour = nil

	hours.each do |space_hour|
		if date.wday == space_hour.day_of_week && (space_hour.effective_date.in_time_zone.midnight == date.in_time_zone.midnight || (!space_hour.one_off && space_hour.effective_date.in_time_zone.midnight <= date.in_time_zone.midnight))
			correct_hour = space_hour
			break
		end
	end

	erb :'admin/home', :layout => :fixed_61, :locals => {
		:user_count => user_count,
		:upcoming_event_count => upcoming_event_count,
		:tool_count => tool_count,
		:space_hour => correct_hour,
		:date => date
	}
end

Dir.glob("#{ROOT}/routes/admin/*.rb") { |file| require file }