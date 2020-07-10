require 'puppet'
require 'yaml'
require 'json'
require 'rest-client'
require 'base64'

Puppet::Reports.register_report(:report2snow) do
  desc "Send corrective changes to ServiceNow"
  @configfile = File.join([File.dirname(Puppet.settings[:config]), "report2snow.yaml"])
  raise(Puppet::ParseError, "Servicenow report config file #{@configfile} not readable") unless File.exist?(@configfile)

  @config = YAML.load_file(@configfile)
  SN_URL = @config['api_url']
  SN_USERNAME = @config['username']
  SN_PASSWORD = @config['password']
  PUPPETCONSOLE = @config['console_url']
  DEBUG = @config['debug']

	def process
    # Open a file for debugging purposes
    logFile = File.open('/var/log/puppetlabs/puppetserver/report2snow.log','a')
    timestamp = Time.now.utc.iso8601
    # We only want to send a report if we have a corrective change
    self.status == "changed" && self.corrective_change == true ? real_status = "#{self.status} (corrective)" : real_status = "#{self.status}" 
    msg = "Puppet run resulted in a status of '#{real_status}'' in the '#{self.environment}' environment"
    logFile.write("[#{timestamp}]: DEBUG: msg: #{msg}\n") if DEBUG == true  
    if real_status == 'changed (corrective)' then
      request_body_map = {
        :active => 'false',
        :category => 'Puppet Corrective Change',
        :description => "#{msg}",
        :escalation => '0',
        :impact => '2',
        :incident_state => '3',
        :priority => '3',
        :severity => '2',
        :short_description => "Puppet Corrective Change on #{self.host}",
        :state => '7',
        :sys_created_by => 'Puppet Enterprise',
	:caller_id => 'Puppet Enterprise',
        :urgency => '2',
        :close_notes => 'New',
        :close_code => 'Solved (Work Around)',
        :work_notes => "Node Reports: [code]<a class='web' target='_blank' href='#{PUPPETCONSOLE}/#/enforcement/node/#{self.host}/reports'>Reports</a>[/code]"
      }
      logFile.write("[#{timestamp}]: DEBUG: payload:\n-------\n#{request_body_map}\n-----\n") if DEBUG == true
      response = RestClient.post("#{SN_URL}",
                                   request_body_map.to_json,    # Encode the entire body as JSON
                                  {
                                    :authorization => "Basic #{Base64.strict_encode64("#{SN_USERNAME}:#{SN_PASSWORD}")}",
                                    :content_type => 'application/json',
                                    :accept => 'application/json'}
                                )
      logFile.write("[#{timestamp}]: DEBUG: response:\n-------\n#{response}\n-----\n") if DEBUG == true
      responseData = JSON.parse(response)
      incidentNumber = responseData['result']['number']
      created = responseData['result']['opened_at']
      logFile.write("[#{timestamp}]: Puppet run on #{self.host} resulted in a status of #{real_status} in the #{self.environment} environment\n")
      logFile.write("[#{timestamp}]: ServiceNow Incident #{incidentNumber} was created on #{created}\n")
    end
    logFile.close
	end
end
