ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

require 'fileutils'
require 'dropbox_sdk'
require 'json'
require 'net/smtp'
require 'logger'
require 'find'
require 'oci8'
require 'to_xml'
require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'

# ---------------------- VARIABLES (HEADER)
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = filename_split.gsub(/[^[:alnum:]\._-]/,'')
basename_normalized = File.basename(filename_normalized, ".*")
extension = File.extname(filename_normalized)
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
tmp_dir=File.join(working_dir, basename_normalized)
validator_dir = File.dirname(__FILE__)
mailer_dir = File.join(validator_dir,'mailer_messages')
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json') 
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
errFile = File.join(project_dir, "ERROR_RUNNING_#{filename_normalized}.txt")

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
pe_pm_file = File.join(validator_dir,'staff_email.json')
errlog = false
no_pm = false
no_pe = false
stylecheck_complete = false 
stylecheck_styled = false
stylecheck_isbns = []
cc_emails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'


#is ituseful to add ccemails to contacts hash?  Should workflows be included?  even if bookinfo.json is not present? (cuz right now is not)



#--------------------- RUN

#get info from status.json
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
	status_hash['docisbn_checkdigit_fail'] = []
	status_hash['docisbn_lookup_fail'] = []	
	status_hash['docisbn_match_fail'] = []
	status_hash['validator_run_ok'] = true
	status_hash['document_styled'] = true
	status_hash['pe_lookup'] = true
	status_hash['pm_lookup'] = true
else
	logger.info('validator_checker') {"status.json not present or unavailable"}
end	


#get info from style_check.json
if File.file?(stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(stylecheck_file)
	stylecheck_complete = stylecheck_hash['completed']
	stylecheck_styled = stylecheck_hash['styled']['pass']
	stylecheck_isbns = stylecheck_hash['isbn']['list']
	logger.info('validator_checker') {"retrieved from style_check.json- styled:\"#{stylecheck_styled}\", complete:\"#{stylecheck_complete}\", isbns:\"#{stylecheck_isbns}\""}

	#get status on run from syle)check items:
	if !stylecheck_complete 
		status_hash['validator_run_ok'] = false
		logger.info('validator_checker') {"stylecheck not complete accirdign to sylecheck.json, flagging for mailer"}
	end	
	if !stylecheck_styled 
		status_hash['document_styled'] = false
		logger.info('validator_checker') {"document not styled according to stylecheck.json, flagging for mailer"}
	end	

else	
	logger.info('validator_checker') {"style_check.json not present or unavailable"}
	status_hash['validator_run_ok'] = false
end	


#get info from bookinfo.json, do pe & pm lookups
#(& setting up handling for cc's)
if File.file?(bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
	pm_name = bookinfo_hash['production_manager'] 
	pe_name = bookinfo_hash['production_editor']
	logger.info('validator_checker') {"retrieved from book_info.json- pe_name:\"#{pe_name}\", pm_name:\"#{pm_name}\""}	
	work_id = bookinfo_hash['work_id']
	author = bookinfo_hash['author']
	title = bookinfo_hash['title']
	imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']

	#read in our static pe/pm json
	pe_pm_hash = Mcmlln::Tools.readjson(pe_pm_file)
	#read in out contacts.json so we can update it with pe/pm:
	if File.file?(contacts_file)
		contacts_hash = Mcmlln::Tools.readjson(contacts_file)
	else
		contacts_hash = []
		logger.info('validator_checker') {"contacts json not found?"}
	end
	
	pm_mail = ''
	pe_mail = ''
	contacts_hash['cc_emails'] = []
	for i in 0..pe_pm_hash.length - 1
		if pm_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
		 	pm_mail = pe_pm_hash[i]['email']
		end
		if pe_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
		 	pe_mail = pe_pm_hash[i]['email']
		end		
	end	
	logger.info('validator_checker') {"retrieved from staff_email.json- pe_mail:\"#{pe_mail}\", pm_mail:\"#{pm_mail}\""}	

	#further handling for cc's for PE's & PM's, also prep for adding to submitter_file json
	if pm_mail =~ /@/ 
		cc_emails << pm_mail 
		cc_address = "#{cc_address}, #{pm_name} <#{pm_mail}>"
		contacts_hash.merge!(production_manager_name: pm_name)
		contacts_hash.merge!(production_manager_email: pm_mail)			
	else 
		status_hash['pm_lookup'] = false	
	end
	if pe_mail =~ /@/
		if pm_mail != pe_mail
			cc_emails << pe_mail 
			cc_address = "#{cc_address}, #{pe_name} <#{pe_mail}>"
		end
		contacts_hash.merge!(production_editor_name: pe_name)
		contacts_hash.merge!(production_editor_email: pe_mail)				
	elsif pe_mail !~ /@/
		status_hash['pe_lookup'] = false	
	end
	
	#add pe/pm emails (if found) to submitter_file
	if status_hash['pm_lookup'] || status_hash['pe_lookup'] && File.file?(contacts_file)
		contacts_hash['cc_emails'] = cc_emails
		contacts_hash['cc_address'] = cc_address
		Vldtr::Tools.write_json(contacts_hash, contacts_file)
	end
else	
	logger.info('validator_checker') {"no book_info.json found, unable to retrieve pe/pm emails"}
	status_hash['pm_lookup'], status_hash['pe_lookup'] = false, false
end		


#crosscheck document isbns via work_id
if File.file?(bookinfo_file) && File.file?(stylecheck_file) && File.file?(status_file)
	stylecheck_isbns.each { |sc_isbn| 
		if sc_isbn != bookinfo_hash['isbn']
			if Vldtr::Tools.checkisbn(sc_isbn)
				thissql = exactSearchSingleKey(sc_isbn, "EDITION_EAN")
				myhash = runPeopleQuery(thissql)
				if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book'] 
					logger.info('validator_checker') {"isbn data-warehouse-lookup for manuscript isbn: #{sc_isbn} failed."}
					status_hash['docisbn_lookup_fail'] << sc_isbn
				else
					sc_work_id = myhash['book']['WORK_ID'][0]
					if sc_work_id != bookinfo_hash['work_id']
						status_hash['docisbn_match_fail'] << sc_isbn
						logger.info('validator_checker') {"isbn mismatch found with manuscript isbn: #{sc_isbn}."}
					end
				end	
			else
				status_hash['docisbn_checkdigit_fail'] << sc_isbn
				logger.info('validator_checker') {"isbn from manuscript failed checkdigit: #{sc_isbn}"}
			end			
		end	
	}
end


#check for alert or other unplanned items in tmp_dir:
if Dir.exist?(tmp_dir)
	Find.find(tmp_dir) { |file|
		if file != stylecheck_file && file != bookinfo_file && file != working_file && file != contacts_file && file != tmp_dir && != status_file
			logger.info('validator_checker') {"error log found in tmpdir: #{file}"}
			logger.info('validator_checker') {"file: #{file}"}
			errlog = true
			status_hash['validator_run_ok'] = false
		end
	}
end


#update status file with new news!
Vldtr::Tools.write_json(status_hash, status_file)


#emailing workflows if pe/pm lookups failed
if (File.file?(bookinfo_file) && (!status_hash['pm_lookup'] || !status_hash['pm_lookup']))
	logger.info('validator_checker') {"pe or pm lookup failed"}	 
	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "Lookup failed: #{project_name} on #{filename_split}"

PE or PM lookup failed for bookmaker_validator:

PE name (from data-warehouse): #{pe_name}
PM name (from data-warehouse): #{pm_name}
PE email (lookup against our static json): #{pe_mail} 
PM email (lookup against our static json): #{pm_mail}

MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
		Vldtr::Tools.sendmail(message, workflows@macmillan.com, '')
		logger.info('validator_checker') {"sent email re failed lookup, now exiting validator_checker"}	 	
	end

end	




