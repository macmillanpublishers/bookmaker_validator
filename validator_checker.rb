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
	status_hash['validator_macro_complete'] = false
	status_hash['document_styled'] = ''
	status_hash['bookmaker_ready'] = false
	status_hash['password_protected'] = false
else
	logger.info {"status.json not present or unavailable"}
end

#get info from style_check.json
if File.file?(Val::Files.stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(Val::Files.stylecheck_file)
  #get status on run from stylecheck items:
	if stylecheck_hash['completed'].nil?
		status_hash['validator_macro_complete'] = false
		logger.info {"stylecheck.json present, but 'complete' value not present, looks like macro crashed"}
	elsif stylecheck_hash['initialize']['password_protected'] == true
		status_hash['password_protected'] = true
		logger.info {"stylecheck.json present, but document is password protected."}
	else
		#set vars for status.json fro stylecheck.json
  	status_hash['validator_macro_complete'] = stylecheck_hash['completed']
  	status_hash['document_styled'] = stylecheck_hash['styled']['pass']
  	logger.info {"retrieved from style_check.json- styled:\"#{status_hash['document_styled']}\", complete:\"#{status_hash['validator_macro_complete']}\""}
  end
else
	logger.info {"style_check.json not present or unavailable"}
	status_hash['validator_macro_complete'] = false
end


#check for alert or other unplanned items in Val::Paths.tmp_dir:
if Dir.exist?(Val::Paths.tmp_dir)
	Find.find(Val::Paths.tmp_dir) { |file|
		if file != Val::Files.stylecheck_file && file != Val::Files.bookinfo_file && file != Val::Files.working_file && file != Val::Files.contacts_file && file != Val::Paths.tmp_dir && file != Val::Files.status_file && file != Val::Files.isbn_file && !File.directory?(file) && file != Val::Files.original_file
			logger.info {"error log found in tmpdir: file: #{file}"}
			status_hash['validator_macro_complete'] = false
		end
	}
end

#if file is ready for bookmaker to run, tag it in status.json so the deploy.rb can scoop it up
if File.file?(Val::Files.bookinfo_file) && status_hash['validator_macro_complete'] && status_hash['document_styled'] == true
	status_hash['bookmaker_ready'] = true
end

#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
