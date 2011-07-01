require 'net/http'
require 'net/https'

module Detrusion

  @@detrusion_config = {
    :white_list => [],
    :black_list => [],
    :patterns => [],
    :synced => false,
    :last_sync => nil,
    :sync_interval => 5.minutes,
    :block_score => 10,
    :redirect => '/blocked.html'
  }
   
  # called from the before_filter of the application controller
  def detrusion_check
    return true unless defined?(DETRUSION_CONFIG)
    
    if @@detrusion_config[:last_sync] == nil or @@detrusion_config[:last_sync] + @@detrusion_config[:sync_interval] < Time.now
      @@detrusion_config[:synced] = false
    end
         
    # sync if required
    detrusion_sync unless @@detrusion_config[:synced]
    
    # analyze and redirect if necessary
    redirect_to @@detrusion_config[:redirect] and return if detrusion_analyze
    
  rescue
    return true
  end
  
  
  def detrusion_analyze
    ip = request.remote_addr
    
    # check whitelist
    return false if @@detrusion_config[:white_list].include?(ip)
    
    # check blacklist
    is_blocked = false
    if @@detrusion_config[:black_list]
      @@detrusion_config[:black_list].each do |blacklisted|
        if blacklisted[:ip] == ip
          is_blocked = blacklisted[:score] >= @@detrusion_config[:block_score]
          break
        end
        
      end
      
    end
    return true if is_blocked
    
    detrusion_report if detrusion_recursive_check(params)
    return is_blocked
  end
  
  def detrusion_recursive_check(value)
    if value.class == ActiveSupport::HashWithIndifferentAccess
      value.each_value do |subvalue|
        return true if detrusion_recursive_check(subvalue)
      end
    else
      @@detrusion_config[:patterns].each do |pattern|
        return true if pattern.match(value)
      end  
    end
    return false
  end
  
  def detrusion_get_https
    # set defaults
    host = DETRUSION_CONFIG[:host] ? DETRUSION_CONFIG[:host] : 'detrusion.com'
    port = DETRUSION_CONFIG[:port] ? DETRUSION_CONFIG[:port] : 443
    ssl  = DETRUSION_CONFIG[:ssl] != nil ? DETRUSION_CONFIG[:ssl] : true
    
    https = Net::HTTP.new(host, port)
    https.use_ssl = ssl
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    return https
  end
  
  def detrusion_report
    https = detrusion_get_https
    success = false

    #response = nil
    https.start { |connection|
        req = Net::HTTP::Post.new('/api/report')
      	req.set_form_data({
      			'email' => DETRUSION_CONFIG[:user],
      			'api' => DETRUSION_CONFIG[:api],
      			'ip' => request.remote_addr,
      			'url' => request.url
        })
      	resp, dat = connection.request(req)	   
      	success = resp.body == 'OK'
      	@@detrusion_config[:synced] = false if success # force resync
      }
    return success
  end
  
  
  def detrusion_sync
    https = detrusion_get_https

    response = nil
    https.start { |connection|
      req = Net::HTTP::Post.new('/api/sync')
    	req.set_form_data({
    			'email' => DETRUSION_CONFIG[:user],
    			'api' => DETRUSION_CONFIG[:api],
    			'url' => request.url
      })
    	resp, dat = connection.request(req)	   
    	response = YAML::load(resp.body)    
    }
    
    #puts response.to_yaml

    # save results in memory
    @@detrusion_config[:white_list] = response[:whitelist]
    @@detrusion_config[:black_list] = response[:blacklist]
    @@detrusion_config[:sync_interval] = response[:sync_interval]
    @@detrusion_config[:block_score] = response[:block_score]
    @@detrusion_config[:redirect] = response[:redirect]
    @@detrusion_config[:patterns] = response[:patterns]
    
    @@detrusion_config[:synced] = true
    @@detrusion_config[:last_sync] = Time.now
    return true
  rescue
    return false
  end
  
end
