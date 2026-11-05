require 'active_record'

class Event < ActiveRecord::Base
	has_many :event_signups, :dependent => :destroy
	has_many :reservation, :dependent => :destroy
	has_many :event_authorizations, :dependent => :destroy
	belongs_to :location
	belongs_to :event_type
	alias_method :type, :event_type
	alias_method :signups, :event_signups

	# Serivce Space ID 1
    EVENT_TYPE_ID_NEW_MEMBER_ORIENTATION = 1
    EVENT_TYPE_ID_MACHINE_TRAINING = 2
    EVENT_TYPE_ID_ADV_SKILL_BASED_WORKSHOP = 3
    EVENT_TYPE_ID_CREATION_WORKSHOP = 4
    EVENT_TYPE_ID_GENERAL_WORKSHOP = 5
    EVENT_TYPE_ID_FREE_EVENT = 6
    EVENT_TYPE_ID_RSVP_ONLY_EVENT = 7
    EVENT_TYPE_ID_TOUR = 8
	EVENT_TYPE_HRC_TRAINING = 11

	# Serivce Space ID 8
	EVENT_TYPE_ID_ENGINEERING_NEW_MEMBER_ORIENTATION = 12
	EVENT_TYPE_ID_ENGINEERING_MACHINE_TRAINING = 13
	EVENT_TYPE_ID_ENGINEERING_GENERAL_WORKSHOP = 14
	EVENT_TYPE_ID_ENGINEERING_WOODSHOP = 15
	EVENT_TYPE_ID_ENGINEERING_METALSHOP = 16
	EVENT_TYPE_ID_ENGINEERING_DIGITAL_FABRICATION = 17

	def self.type_options
		# These correspond with event_types table
		if SS_ID == 1
			{
				EVENT_TYPE_ID_NEW_MEMBER_ORIENTATION => 'New Member Orientation',
				EVENT_TYPE_ID_MACHINE_TRAINING => 'Machine Training',
				EVENT_TYPE_ID_ADV_SKILL_BASED_WORKSHOP => 'Advanced Skill-Based Workshop',
				EVENT_TYPE_ID_CREATION_WORKSHOP => 'Creation Workshop',
				EVENT_TYPE_ID_GENERAL_WORKSHOP => 'General Workshop',
				EVENT_TYPE_ID_FREE_EVENT => 'Free Event',
				EVENT_TYPE_ID_RSVP_ONLY_EVENT => 'RSVP Only Event',
				EVENT_TYPE_HRC_TRAINING => 'HRC Training',
			}
		elsif SS_ID == 8
			{
				EVENT_TYPE_ID_ENGINEERING_NEW_MEMBER_ORIENTATION => 'New Member Orientation',
				EVENT_TYPE_ID_ENGINEERING_MACHINE_TRAINING => 'Machine Training',
				EVENT_TYPE_ID_ENGINEERING_GENERAL_WORKSHOP => 'General Workshop',
				EVENT_TYPE_ID_ENGINEERING_WOODSHOP => 'Woodshop',
				EVENT_TYPE_ID_ENGINEERING_METALSHOP => 'Metalshop',
				EVENT_TYPE_ID_ENGINEERING_DIGITAL_FABRICATION => 'Digital Fabrication',
			}
		end
    end

    EVENT_TYPES_NOT_ALLOWED_FOR_SIGNUP = []

	scope :in_day, ->(time) {
		day_start = time.in_time_zone.beginning_of_day
		day_end = day_start + 1.day

		# Include any event that overlaps this day at all
		where('start_time < ? AND end_time > ?', day_end.utc, day_start.utc)
	}

		scope :in_week, ->(time) {
		week_start = time.in_time_zone.beginning_of_week  # usually Monday, change if you use Sunday
		week_end = week_start + 1.week

		# Include any event that overlaps this week
		where('start_time < ? AND end_time > ?', week_end.utc, week_start.utc)
	}

	# returns length in minutes. If start or end is nil, returns 0
	def length
		if end_time.nil? || start_time.nil?
			return 0
		end
		((end_time - start_time) / 60).to_i
	end

	def info_link
		case type.description
		when 'New Member Orientation'
			"/new_members/sign_up/#{id}/"
		else
			"/events/#{id}/"
		end
	end

	def edit_link
		"/admin/events/#{id}/edit/"
	end

	def has_reservation
		!self.reservation.nil? && self.reservation.count > 0
	end

	def has_tool_reservation(tool_id)
	    return false unless self.has_reservation
	    self.reservation.each do |r|
	        return true if !r.resource.nil? && r.resource.id == tool_id
	    end
	    false
	end

	def has_authorization
		!self.event_authorizations.nil? && self.event_authorizations.count > 0
	end

	def image_src
		"/images/#{id}/"
	end

	def set_data(params, date_data)

		self.title = params[:title]
		self.description = params[:description]
		self.admin_notes = params[:admin_notes]
		if params[:timeless_event_checkbox] != "on"
			self.start_time = calculate_time(date_data[:start_date], date_data[:start_time_hour], date_data[:start_time_minute], date_data[:start_time_am_pm])
			self.end_time = calculate_time(date_data[:end_date], date_data[:end_time_hour], date_data[:end_time_minute], date_data[:end_time_am_pm])
		else
			self.start_time = nil
			self.end_time = nil
		end
		self.event_type_id = params[:type]
		self.trainer_id = params[:trainer]
		self.trainer_2_id = params[:trainer_2]
		self.trainer_3_id = params[:trainer_3]
		self.location_id = params[:location]
		self.max_signups = params[:limit_signups] == 'on' ? params[:max_signups].to_i : nil
		self.area = !params[:area].nil? ? params[:area] : nil
		self.service_space_id = SS_ID
		if params[:is_private].nil?
			self.is_private = 0
		else
			self.is_private = params[:is_private]
		end
		if params[:hrc_feed].nil?
			self.hrc_feed = 0
		else
			self.hrc_feed = 1
		end
		if params[:hrc_parking].nil?
			self.hrc_parking = 0
		else
			self.hrc_parking = 1
		end
		self.event_code = params[:event_code]
		self.payment_link = params[:payment_link]
		self.save
	end

	def set_image_data(params)
		if params[:imagedata]
			self.imagemime = params[:imagedata][:type]
			self.imagedata = params[:imagedata][:tempfile].read if params[:imagedata][:tempfile].is_a?(Tempfile)
		end
		self.save
	end

	def remove_image_data
		self.imagemime = nil
		self.imagedata = nil
		self.save
	end

	def signup_allowed_for_type?
	    !EVENT_TYPES_NOT_ALLOWED_FOR_SIGNUP.include?(self.type.id)
	end

	def free_event_type?
	    self.type.id == EVENT_TYPE_ID_FREE_EVENT
	end

	def hrc_training?
	    self.type.id == EVENT_TYPE_HRC_TRAINING
	end

	def machine_training_event_type?
	    self.type.id == EVENT_TYPE_ID_MACHINE_TRAINING || self.type.id == EVENT_TYPE_ID_ENGINEERING_MACHINE_TRAINING
	end
end
