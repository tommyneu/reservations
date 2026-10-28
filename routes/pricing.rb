require 'models/material_price'

get '/pricing/?' do
	@breadcrumbs << {:text => 'Material Pricing'}
	material_prices = Material_Price.where(:service_space_id => SS_ID).order(category: :asc, subcategory: :asc, name: :asc).all.to_a

	erb :pricing, :layout => :fixed_61, :locals => {
		:material_prices => material_prices
	}
end
