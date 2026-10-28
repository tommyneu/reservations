require 'models/alert'
require 'models/alert_signup'

get '/alert_center/:user_id/?' do

    user_alerts = AlertSignup.joins(:alert).where('user_id = ?', @user.id)
    alert_ids = Array.new

    user_alerts.each do |alert|
        alert_ids.append(alert.alert_id)
    end

    generalAlerts = nil
    woodShopAlerts = nil
    metalShopAlerts = nil
    digitalFabricationAlerts = nil
    artAlerts = nil

    if SS_ID == 1
        generalAlerts = Alert.all.where(category_id: 1).to_a
        generalAlerts.sort_by! do |generalAlerts|
            [
                generalAlerts.name.to_s.downcase,
                generalAlerts.description.to_s.downcase
            ]
        end

        woodShopAlerts = Alert.all.where(category_id: 2).to_a
        woodShopAlerts.sort_by! do |woodShopAlerts|
            [
                woodShopAlerts.name.to_s.downcase,
                woodShopAlerts.description.to_s.downcase
            ]
        end

        metalShopAlerts = Alert.all.where(category_id: 3).to_a
        metalShopAlerts.sort_by! do |metalShopAlerts|
            [
                metalShopAlerts.name.to_s.downcase,
                metalShopAlerts.description.to_s.downcase
            ]
        end

        digitalFabricationAlerts = Alert.all.where(category_id: 4).to_a
        digitalFabricationAlerts.sort_by! do |digitalFabricationAlerts|
            [
                digitalFabricationAlerts.name.to_s.downcase,
                digitalFabricationAlerts.description.to_s.downcase
            ]
        end

        artAlerts = Alert.all.where(category_id: 5).to_a
        artAlerts.sort_by! do |artAlerts|
            [
                artAlerts.name.to_s.downcase,
                artAlerts.description.to_s.downcase
            ]
        end

    elsif SS_ID == 8
        generalAlerts = Alert.all.where(category_id: 6).to_a
        generalAlerts.sort_by! do |generalAlerts|
            [
                generalAlerts.name.to_s.downcase,
                generalAlerts.description.to_s.downcase
            ]
        end

        woodShopAlerts = Alert.all.where(category_id: 7).to_a
        woodShopAlerts.sort_by! do |woodShopAlerts|
            [
                woodShopAlerts.name.to_s.downcase,
                woodShopAlerts.description.to_s.downcase
            ]
        end

        metalShopAlerts = Alert.all.where(category_id: 8).to_a
        metalShopAlerts.sort_by! do |metalShopAlerts|
            [
                metalShopAlerts.name.to_s.downcase,
                metalShopAlerts.description.to_s.downcase
            ]
        end

        digitalFabricationAlerts = Alert.all.where(category_id: 9).to_a
        digitalFabricationAlerts.sort_by! do |digitalFabricationAlerts|
            [
                digitalFabricationAlerts.name.to_s.downcase,
                digitalFabricationAlerts.description.to_s.downcase
            ]
        end
    end

    erb :alert_center, :layout => :fixed_61, :locals => {
        :generalAlerts => generalAlerts,
        :woodShopAlerts => woodShopAlerts,
        :metalShopAlerts => metalShopAlerts,
        :digitalFabricationAlerts => digitalFabricationAlerts,
        :artAlerts => artAlerts,
        :alert_ids => alert_ids
    }

end

post '/alert_center/:user_id/?' do

    newAlerts = Array.new

    params.each do |key, value|
        if key.start_with?('alert_id_')
            newAlerts.append(params[key].to_i)
        end
    end

    users = AlertSignup.where(user_id: @user.id).all
    users.destroy_all

    newAlerts.each do |alert|
        user_alert = AlertSignup.create(user_id: @user.id, alert_id: alert)
    end

    flash(:success, 'Alerts Updated', "Your selected alerts have been saved.")

    redirect '/home/'

end