

get '/admin/maker_request_archive/?' do
	require_login
	@breadcrumbs << {:text => 'Maker Request Archive'}

	maker_requests = Maker_Request.
        where("created < DATE_SUB(NOW(), INTERVAL #{Maker_Request::EXPIRATION_DAYS} DAY)").
        order(created: :desc).all
    erb :'admin/maker_request_list', :layout => :fixed_61, :locals => {
        maker_requests: maker_requests
    }
end