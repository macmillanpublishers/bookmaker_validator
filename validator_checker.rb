require 'fileutils'
require 'find'

require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

pe_pm_file = File.join(Val::Paths.scripts_dir,'staff_email.json')
cc_emails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'



#--------------------- RUN
#get info from status.json, set local vars for status_hash (Had several of these values set as empty but then they eval as true in some if statements)
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
	status_hash['validator_macro_complete'] = false
	status_hash['document_styled'] = false
	status_hash['pe_lookup'] = true
	status_hash['pm_lookup'] = true
	status_hash['bookmaker_ready'] = false
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
	else
		#set vars for status.json fro stylecheck.json
  	status_hash['validator_macro_complete'] = stylecheck_hash['completed']
  	status_hash['document_styled'] = stylecheck_hash['styled']['pass']
  	#stylecheck_isbns = stylecheck_hash['isbn']['list']
		#logger.info {"retrieved from style_check.json- styled:\"#{status_hash['document_styled']}\", complete:\"#{status_hash['validator_macro_complete']}\", isbns:\"#{stylecheck_isbns}\""}
  	logger.info {"retrieved from style_check.json- styled:\"#{status_hash['document_styled']}\", complete:\"#{status_hash['validator_macro_complete']}\""}
  end
else
	logger.info {"style_check.json not present or unavailable"}
	status_hash['validator_macro_complete'] = false
end


#get info from bookinfo.json, do pe & pm lookups (& setting up handling for cc's)
if File.file?(Val::Files.bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(Val::Files.bookinfo_file)
	pm_name = bookinfo_hash['production_manager']
	pe_name = bookinfo_hash['production_editor']
	logger.info {"retrieved from book_info.json- pe_name:\"#{pe_name}\", pm_name:\"#{pm_name}\""}
	work_id = bookinfo_hash['work_id']
	author = bookinfo_hash['author']
	title = bookinfo_hash['title']
	imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']

	#read in our static pe/pm json
	pe_pm_hash = Mcmlln::Tools.readjson(pe_pm_file)

	#read in out contacts.json so we can update it with pe/pm:
	if File.file?(Val::Files.contacts_file)
		contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
	else
		contacts_hash = {}
		logger.info {"contacts json not found?"}
	end

	pm_mail = ''
	pe_mail = ''
	#contacts_hash['cc_emails'] = ''
	for i in 0..pe_pm_hash.length - 1
		if pm_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
		 	pm_mail = pe_pm_hash[i]['email']
		end
		if pe_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
		 	pe_mail = pe_pm_hash[i]['email']
		end
	end
	logger.info {"retrieved from staff_email.json- pe_mail:\"#{pe_mail}\", pm_mail:\"#{pm_mail}\""}

	#add PE's & PM's to submitter_file json
	if pm_mail =~ /@/
		contacts_hash.merge!(production_manager_name: pm_name)
		contacts_hash.merge!(production_manager_email: pm_mail)
	else
		status_hash['pm_lookup'] = false
	end
	if pe_mail =~ /@/
		contacts_hash.merge!(production_editor_name: pe_name)
		contacts_hash.merge!(production_editor_email: pe_mail)
	elsif pe_mail !~ /@/
		status_hash['pe_lookup'] = false
	end
	#add pe/pm emails (if found) to submitter_file
	if status_hash['pm_lookup'] || status_hash['pe_lookup'] && File.file?(Val::Files.contacts_file)
		Vldtr::Tools.write_json(contacts_hash, Val::Files.contacts_file)
	end
else
	logger.info {"no book_info.json found, unable to retrieve pe/pm emails"}
	status_hash['pm_lookup'], status_hash['pe_lookup'] = false, false
end


# #crosscheck document isbns via work_id
# if File.file?(Val::Files.bookinfo_file) && File.file?(Val::Files.stylecheck_file) && File.file?(Val::Files.status_file)
# 	stylecheck_isbns.each { |sc_isbn|
# 		sc_isbn = sc_isbn.to_s.gsub(/-/,'')
# 		if sc_isbn != bookinfo_hash['isbn']
# 			if Vldtr::Tools.checkisbn(sc_isbn)
# 				thissql = exactSearchSingleKey(sc_isbn, "EDITION_EAN")
# 				myhash = runQuery(thissql)
# 				if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book']
# 					logger.info {"isbn data-warehouse-lookup for manuscript isbn: #{sc_isbn} failed."}
# 					status_hash['docisbn_lookup_fail'] << sc_isbn
# 				else
# 					sc_work_id = myhash['book']['WORK_ID']
# 					if sc_work_id != bookinfo_hash['work_id']
# 						status_hash['docisbn_match_fail'] << sc_isbn
# 						logger.info {"isbn mismatch found with manuscript isbn: #{sc_isbn}."}
# 					end
# 				end
# 			else
# 				status_hash['docisbn_checkdigit_fail'] << sc_isbn
# 				logger.info {"isbn from manuscript failed checkdigit: #{sc_isbn}"}
# 			end
# 		end
# 	}
# end


#check for alert or other unplanned items in Val::Paths.tmp_dir:
if Dir.exist?(Val::Paths.tmp_dir)
	Find.find(Val::Paths.tmp_dir) { |file|
		if file != Val::Files.stylecheck_file && file != Val::Files.bookinfo_file && file != Val::Files.working_file && file != Val::Files.contacts_file && file != Val::Paths.tmp_dir && file != Val::Files.status_file && file != Val::Files.isbn_file
			logger.info {"error log found in tmpdir: file: #{file}"}
			status_hash['validator_macro_complete'] = false
		end
	}
end

#if file is ready for bookmaker to run, tag it in status.json so the deploy.rb can scoop it up
if File.file?(Val::Files.bookinfo_file) && status_hash['validator_macro_complete'] && status_hash['document_styled']
	status_hash['bookmaker_ready'] = true
end


#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)


#emailing workflows if pe/pm lookups failed
if (File.file?(Val::Files.bookinfo_file) && (!status_hash['pm_lookup'] || !status_hash['pm_lookup']))
	logger.info {"pe or pm lookup failed"}

	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "Lookup failed: #{Val::Paths.project_name} on #{Val::Doc.filename_split}"

PE or PM lookup failed for bookmaker_validator:

PE name (from data-warehouse): #{pe_name}
PM name (from data-warehouse): #{pm_name}
PE email (lookup against our static json): #{pe_mail}
PM email (lookup against our static json): #{pm_mail}
MESSAGE_END

	#now sending
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message, 'workflows@macmillan.com', '')
		logger.info {"sent email re failed lookup, now exiting validator_checker"}
	end
end
