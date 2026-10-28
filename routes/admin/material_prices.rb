require 'models/material_price'
require 'models/permission'

before '/admin/material_prices*' do
	unless has_permission?(Permission::MANAGE_RESOURCES)
		raise Sinatra::NotFound
	end
end

get '/admin/material_prices/?' do
	require_login
	@breadcrumbs << {:text => 'Admin Material Prices'}

	material_prices = Material_Price.where(:service_space_id => SS_ID).order(category: :asc, subcategory: :asc, name: :asc).all.to_a
	erb :'admin/material_prices', :layout => :fixed_61, :locals => {
		:material_prices => material_prices
	}
end

post '/admin/material_prices/?' do
	require_login
	@breadcrumbs << {:text => 'Admin Material Prices'}

	# Loop through all id with index
		# if id is new create new row
		# if id is number
			# find row with that id number
			# update the row with the values in name, price, price unit
	# Loop through all deleted
		# find row with that id number
			# delete the row


	output_string = ""
	output_string += "<pre>#{params.inspect}</pre>"

	unless params[:id].nil?
		unless params[:id].is_a?(Array)
			flash(:alert, 'Invalid ID value', "There should always be a list of IDs, even if it is just one")
			redirect back
		end
	
		unless params[:category].is_a?(Array)
			flash(:alert, 'Invalid category value', "There should always be a list of categories, even if it is just one")
			redirect back
		end
	
		unless params[:subcategory].is_a?(Array)
			flash(:alert, 'Invalid subcategory value', "There should always be a list of subcategories, even if it is just one")
			redirect back
		end
	
		unless params[:name].is_a?(Array)
			flash(:alert, 'Invalid name value', "There should always be a list of names, even if it is just one")
			redirect back
		end
	
		unless params[:price].is_a?(Array)
			flash(:alert, 'Invalid price value', "There should always be a list of prices, even if it is just one")
			redirect back
		end
	
		unless params[:unit].is_a?(Array)
			flash(:alert, 'Invalid unit value', "There should always be a list of units, even if it is just one")
			redirect back
		end

		# Check if all the arrays are the same size
		size_check = [
			params[:id],
			params[:category],
			params[:subcategory],
			params[:price],
			params[:unit]
		]
		unless size_check.map(&:length).uniq.size == 1
			flash(:alert, 'Missing Value', "There is a value missing from one of the groups id, category, subcategory, price, unit")
			redirect back
		end
	
		params[:id].each_with_index do |id_value, index|

			if params[:category][index].blank?
				flash(:alert, 'Invalid category value', "Missing category value")
				redirect back
			end

			if params[:name][index].blank?
				flash(:alert, 'Invalid name value', "Missing name value")
				redirect back
			end
			
			if params[:price][index].blank?
				flash(:alert, 'Invalid price value', "Missing price value")
				redirect back
			end

			subcategory_value = params[:subcategory][index]
			if params[:subcategory][index].blank?
				subcategory_value = nil
			end

			unit_value = params[:unit][index]
			if params[:unit][index].blank?
				unit_value = nil
			end
			
			if id_value == "new"
				price_to_create = Material_Price.new
				price_to_create.service_space_id = SS_ID
				price_to_create.category = params[:category][index]
				price_to_create.subcategory = subcategory_value
				price_to_create.name = params[:name][index]
				price_to_create.price_cents = (params[:price][index].to_f * 100).to_i
				price_to_create.price_per_unit = unit_value
				price_to_create.save
			else
				price_to_update = Material_Price.find_by(:id => id_value, :service_space_id => SS_ID)
				price_to_update.category = params[:category][index]
				price_to_update.subcategory = subcategory_value
				price_to_update.name = params[:name][index]
				price_to_update.price_cents = (params[:price][index].to_f * 100).to_i
				price_to_update.price_per_unit = unit_value
				price_to_update.save
			end
		end
	end

	unless params[:deleted_id].nil?
		unless params[:deleted_id].is_a?(Array)
			flash(:alert, 'Invalid deleted ID value', "There should always be a list of deleted IDs, even if it is just one")
			redirect back
		end
	
		params[:deleted_id].each_with_index do |id_value, index|
			price_to_delete = Material_Price.find_by(:id => id_value, :service_space_id => SS_ID)
			price_to_delete.destroy
		end
	end

	flash(:success, 'Material Prices Saved', "Your material prices have been successfully saved.")
	redirect back
end