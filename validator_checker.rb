require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger


#--------------------- RUN
#get info from status.json, set local vars for status_hash (Had several of these values set as empty but then they eval as true in some if statements)
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
	status_hash['validator_py_complete'] = 'n-a'
	status_hash['percent_styled'] = nil
  status_hash['document_styled'] = 'n-a'
	status_hash['bookmaker_ready'] = false
else
	logger.info {"status.json not present or unavailable"}
end

if status_hash['val_py_started'] == true
	#get info from stylereport_json
	case
	when !File.file?(Val::Files.stylereport_json)
	  status_hash['validator_py_complete'] = false
	  logger.info {"stylereport_json not present"}
	when Val::Hashes.stylereport_hash.empty?
	  status_hash['validator_py_complete'] = false
	  logger.info {"stylereport_json not present"}
	when !Val::Hashes.stylereport_hash.has_key?('validator_py_complete')
	  status_hash['validator_py_complete'] = false
	  logger.info {"stylecheck_hash key 'validator_py_complete' not present"}
	when Val::Hashes.stylereport_hash['validator_py_complete'] != true
	  status_hash['validator_py_complete'] = false
	  logger.info {"stylecheck_hash key 'validator_py_complete' value is \"#{Val::Hashes.stylereport_hash['validator_py_complete']}\""}
	when Val::Hashes.stylereport_hash['validator_py_complete'] == true && File.file?(Val::Files.stylereport_txt)
	  status_hash['validator_py_complete'] = true
	  status_hash['percent_styled'] = Val::Hashes.stylereport_hash['percent_styled']
	  logger.info {"retrieved from style_check.json- styled:\"#{Val::Hashes.stylereport_hash['percent_styled']}\", complete:\"#{status_hash['validator_py_complete']}\""}
	else
	  status_hash['validator_py_complete'] = false
	  logger.info {"unknown err checking on validator_py status, marking \"validator_py_complete\" as false"}
	end
end

# check if doc is styled, log etc
if !status_hash['percent_styled'].nil? && status_hash['percent_styled'].to_i >= 50
  status_hash['document_styled'] = true
elsif !status_hash['percent_styled'].nil?
  status_hash['document_styled'] = false
	# log to alerts.json as notice
	Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "notice", Val::Hashes.alertmessages_hash["notices"]["unstyled"]["message"])
end

# check if we already have presenting errors:
if !Val::Hashes.alerts_hash.has_key?('error') && status_hash['validator_py_complete'] == false
  # log to alerts.json as error
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["validator_error"]["message"].gsub(/PROJECT/,Val::Paths.project_name))
  status_hash['status'] = 'validator error'
end

#if file is ready for bookmaker to run, tag it in status.json so the deploy.rb can scoop it up
if File.file?(Val::Files.bookinfo_file) && status_hash['validator_py_complete'] == true && status_hash['document_styled'] == true
	status_hash['bookmaker_ready'] = true
end

#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
