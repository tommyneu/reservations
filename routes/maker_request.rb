require 'models/maker_request'

get '/maker_request/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'Create Maker Request'}

    erb :maker_request, :layout => :fixed_61, :locals => {
        maker_request: Maker_Request.new(),
        extras: {confirm_email: ''}
    }
end

get '/maker_request/how_to' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'How To'}
    require_login

    erb :maker_request_how_to, :layout => :fixed_61, :locals => {}
end

get '/maker_request/:maker_request_id/view/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'View Maker Request'}

    maker_request = Maker_Request.find(params[:maker_request_id])
    # can only view open requests
    not_found if maker_request.nil? || maker_request.status_id != Maker_Request::STATUS_OPEN

    erb :maker_request_view, :layout => :fixed_61, :locals => {
        maker_request: maker_request
    }
end

get '/maker_request/:maker_request_uuid/edit/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'Edit Maker Request'}

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    erb :maker_request, :layout => :fixed_61, :locals => {
        maker_request: maker_request,
        extras: {
            confirm_email: maker_request.requestor_email,
            confirm_read_disclaimer: 1
        }
    }
end

get '/maker_request/:maker_request_uuid/manage/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'Manage Maker Request'}

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    erb :maker_request_manage, :layout => :fixed_61, :locals => {
        maker_request: maker_request
    }
end

get '/maker_request/:maker_request_uuid/open/?' do
    not_found if SS_ID != 1

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    unless maker_request.status_id == Maker_Request::STATUS_OPEN
        maker_request.status_id = Maker_Request::STATUS_OPEN
        maker_request.updated = Time.current.strftime('%Y-%m-%d %H:%M:%S')
        maker_request.save
    end

    flash :success, 'Maker Request Opened', 'Your maker request has been opened.'
    redirect "/maker_request/#{maker_request.uuid}/manage/"
end

get '/maker_request/:maker_request_uuid/close/?' do
    not_found if SS_ID != 1

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    unless maker_request.status_id == Maker_Request::STATUS_CLOSED
        maker_request.status_id = Maker_Request::STATUS_CLOSED
        maker_request.updated = Time.current.strftime('%Y-%m-%d %H:%M:%S')
        maker_request.save
    end

    flash :success, 'Maker Request Closed', 'Your maker request has been closed.'
    redirect "/maker_request/#{maker_request.uuid}/manage/"
end

get '/maker_request/:maker_request_uuid/delete/?' do
    not_found if SS_ID != 1

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    maker_request.pdf_delete
    maker_request.destroy

    flash :success, 'Maker Request Deleted', 'Your maker request has been deleted.'
    if @user.nil?
        redirect '/maker_request/'
    else
        redirect '/maker_request/list/'
    end
end

post '/maker_request/?' do
    not_found if SS_ID != 1

    extras = {
        confirm_email: params[:confirm_email],
        confirm_read_disclaimer: params[:confirm_read_disclaimer],
        pdf_document: params[:pdf_document]
    }
    params.delete('confirm_email')
    params.delete('confirm_read_disclaimer')
    params.delete('pdf_document')

    maker_request = Maker_Request.new(params)

    errors = maker_request.form_validate(extras)

    if errors.empty?
        maker_request.uuid = sprintf("%20.10f", Time.now.to_f).delete('.').to_i.to_s(36)
        maker_request.status_id = Maker_Request::STATUS_OPEN
        maker_request.created = Time.current.strftime('%Y-%m-%d %H:%M:%S')
        maker_request.updated = Time.current.strftime('%Y-%m-%d %H:%M:%S')
        maker_request.save
        maker_request.pdf_write(extras[:pdf_document][:tempfile]) if !extras[:pdf_document].nil?

        # send email to requestor
        email_subject = 'Innovation Studio Manager Maker Request'
        email_body = "#{maker_request.requestor_name},<br><br>Your Innovation Studio Manager Maker Request has been posted.  " \
                     "Please keep this email for you records. You may manage your request here: http://#{request.host}/maker_request/#{maker_request.uuid}/manage. " \
                     "When someone has picked up your request, please delete it from the list. " \
                     "Maker requests will expire after #{Maker_Request::EXPIRATION_DAYS} days and will not " \
                     'display in the Maker Request List. If your request has expired and you’d like to renew it, you will need to create a new request.'
        Emailer.mail(maker_request.requestor_email, email_subject, email_body)

        flash :success, 'Maker Request Created', "Your maker request has been created. You should receive a confirmation email at #{params[:requestor_email]}."
        redirect "/maker_request/#{maker_request.uuid}/manage/"
    end

    # display errors
    errors.each { |error| flash :alert, error[:heading], error[:message] }

    erb :maker_request, :layout => :fixed_61, :locals => {
        maker_request: maker_request,
        extras: extras
    }
end

post '/maker_request/:maker_request_uuid/edit/?' do
    not_found if SS_ID != 1

    maker_request = Maker_Request.find_by(uuid: params[:maker_request_uuid])
    not_found if maker_request.nil?

    # set updated attributes
    maker_request.requestor_name =  params[:requestor_name]
    maker_request.requestor_email =  params[:requestor_email]
    maker_request.requestor_phone =  params[:requestor_phone]
    maker_request.category_id =  params[:category_id]
    maker_request.title =  params[:title]
    maker_request.description =  params[:description]
    maker_request.updated = Time.current.strftime('%Y-%m-%d %H:%M:%S')

    extras = {
        confirm_email: params[:confirm_email],
        confirm_read_disclaimer: params[:confirm_read_disclaimer],
        pdf_document: params[:pdf_document],
        remove_pdf_document: params[:remove_pdf_document]
    }
    params.delete('confirm_email')
    params.delete('confirm_read_disclaimer')
    params.delete('pdf_document')
    params.delete('remove_pdf_document')

    errors = maker_request.form_validate(extras)

    if errors.empty?
        maker_request.save
        maker_request.pdf_delete if !extras[:remove_pdf_document].nil?
        maker_request.pdf_write(extras[:pdf_document][:tempfile]) if !extras[:pdf_document].nil?

        flash :success, 'Maker Request Saved', 'Your maker request has been saved.'
        redirect "/maker_request/#{maker_request.uuid}/manage/"
    end

    # display errors
    errors.each { |error| flash :alert, error[:heading], error[:message] }

    erb :maker_request, :layout => :fixed_61, :locals => {
        maker_request: maker_request,
        extras: extras
    }
end


get '/maker_request/list/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'Maker Request List'}
    require_login

    maker_requests = Maker_Request.
        where(status_id: Maker_Request::STATUS_OPEN).
        where("created > DATE_SUB(NOW(), INTERVAL #{Maker_Request::EXPIRATION_DAYS} DAY)").
        order(category_id: :desc, created: :asc).all
    erb :maker_request_list, :layout => :fixed_61, :locals => {
        maker_requests: maker_requests
    }
end

get '/maker_request/lookup/?' do
    not_found if SS_ID != 1

    @breadcrumbs << {:text => 'Maker Request Lookup'}

    lookup_email = ''
    lookup_email = @user.email unless @user.nil?

    maker_requests = []
    unless lookup_email.empty?
        maker_requests = Maker_Request.where(requestor_email: lookup_email).order(category_id: :desc, created: :asc).all
    end

    erb :maker_request_lookup, :layout => :fixed_61, :locals => {
        lookup_email: lookup_email,
        maker_requests: maker_requests
    }
end

post '/maker_request/lookup/?' do
    not_found if SS_ID != 1

    maker_requests = []
    if params[:lookup_email].nil? || params[:lookup_email].strip.empty?
        flash :alert, 'Lookup Email', 'Please provide an email to lookup'
    elsif !params[:lookup_email].strip.match(Maker_Request::VALID_EMAIL_REGEX)
        flash :alert, 'Lookup Email', 'Please provide a valid email to lookup'
    else
        maker_requests = Maker_Request.where(requestor_email: params[:lookup_email].strip).order(category_id: :desc, created: :asc).all
        unless maker_requests.empty?
            # send email to requestor
            email_subject = 'Innovation Studio Manager Maker Request Lookup'
            email_body = 'The following maker requests are associated to your email:<ul>'
            maker_requests.each do |maker_request|
                email_body << "<li>#{maker_request.title} - http://#{request.host}/maker_request/#{maker_request.uuid}/manage</li>"
                email_body << "<br>"
            end
            email_body << "</ul>"
            Emailer.mail(params[:lookup_email].strip, email_subject, email_body)
        end
        # Send success whether email had requests or not so email cannot be validated via form
        flash :success, 'Lookup Email Sent', "An email with all of your maker requests has been sent to #{params[:lookup_email]} if you had any."
    end

    redirect back
end



