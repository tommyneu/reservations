get '/training-documents/?' do
	not_found if SS_ID != 1

	@breadcrumbs << {:text => 'Training Documents'}
	erb :training_documents, :layout => :fixed_61
end


get '/training-documents/sop/?' do
	not_found if SS_ID != 1

	redirect '/training-documents/'
end
