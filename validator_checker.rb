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

# if File.file?(Val::Files.stylecheck_file)
# 	stylecheck_hash = Mcmlln::Tools.readjson(Val::Files.stylecheck_file)
# 	#get status on run from stylecheck items:
# 	if stylecheck_hash['completed'].nil?
# 		status_hash['validator_py_complete'] = false
# 		logger.info {"stylecheck.json present, but 'complete' value not present, looks like macro crashed"}
# 		# log to alerts.json as error
# 		Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["validator_error"]["message"].gsub(/PROJECT/,Val::Paths.project_name))
# 		status_hash['status'] = 'validator error'
# 	else
# 		#set vars for status.json fro stylecheck.json
# 		status_hash['validator_py_complete'] = stylecheck_hash['completed']
# 		status_hash['document_styled'] = stylecheck_hash['styled']['pass']
# 		logger.info {"retrieved from style_check.json- styled:\"#{status_hash['document_styled']}\", complete:\"#{status_hash['validator_py_complete']}\""}
# 	end
# else
# 	logger.info {"style_check.json not present or unavailable"}
# 	status_hash['validator_py_complete'] = false
# 	# log to alerts.json as error
# 	Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["validator_error"]["message"].gsub(/PROJECT/,Val::Paths.project_name))
# 	status_hash['status'] = 'validator error'
# end

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

# #check for alert or other unplanned items in Val::Paths.tmp_dir:
# if Dir.exist?(Val::Paths.tmp_dir)
# 	unknownfile_found = false
# 	Find.find(Val::Paths.tmp_dir) { |file|
# 		if file != Val::Files.stylecheck_file && file != Val::Files.bookinfo_file && file != Val::Files.working_file && file != Val::Files.contacts_file && file != Val::Paths.tmp_dir && file != Val::Files.status_file && file != Val::Files.isbn_file && !File.directory?(file) && file != Val::Files.original_file && file != Val::Files.alerts_json
# 			logger.info {"error log found in tmpdir: file: #{file}"}
# 			unknownfile_found = true
# 		end
# 	}
#   # make sure we are not duplicating an error already generated
# 	if unknownfile_found == true && File.file?(Val::Files.stylecheck_file) && !stylecheck_hash['completed'].nil?
# 		# log to alerts.json as error
# 		Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["validator_error"]["message"].gsub(/PROJECT/,Val::Paths.project_name))
# 		status_hash['status'] = 'validator error'
# 		status_hash['validator_py_complete'] = false
# 	end
# end

#if file is ready for bookmaker to run, tag it in status.json so the deploy.rb can scoop it up
if File.file?(Val::Files.bookinfo_file) && status_hash['validator_py_complete'] == true && status_hash['document_styled'] == true
	status_hash['bookmaker_ready'] = true
end

#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
