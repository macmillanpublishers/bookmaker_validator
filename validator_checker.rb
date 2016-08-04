require 'fileutils'
require 'find'

require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

staff_file = File.join(Val::Paths.scripts_dir,'staff_email.json')
staff_defaults_file = File.join(Val::Paths.scripts_dir,'defaults.json')
cc_emails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'


# ---------------------- FUNCTIONS
def staff_lookup(pm_or_pe, name, staff_hash, submitter_mail, staff_defaults_hash)
	mail = 'not found'
	if name == "not found"    #no name associated in biblio, lookup backup PM/PE via submitter division
		status = "not in biblio"
		for i in 0..staff_hash.length - 1
			if submitter_mail == staff_hash[i]['email']
				submitter_div = staff_hash[i]['division']
				mail = staff_defaults_hash[submitter_div][pm_or_pe]
			end
		end
		if mail == 'not found' then mail = 'workflows@macmillan.com' end	#this means dropbox api failed, just sentall emails to Workflows
	else
		for i in 0..staff_hash.length - 1
			if name == "#{staff_hash[i]['firstName']} #{staff_hash[i]['lastName']}"
				mail = staff_hash[i]['email']
				status = 'ok'
			end
		end
		if mail == 'not found' then status = 'not in json'; mail = 'workflows@macmillan.com' end
	end
	return mail, status
end


#--------------------- RUN
#get info from status.json, set local vars for status_hash (Had several of these values set as empty but then they eval as true in some if statements)
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
	status_hash['validator_macro_complete'] = false
	status_hash['document_styled'] = false
	status_hash['pe_lookup'] = ''
	status_hash['pm_lookup'] = ''
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
  	logger.info {"retrieved from style_check.json- styled:\"#{status_hash['document_styled']}\", complete:\"#{status_hash['validator_macro_complete']}\""}
  end
else
	logger.info {"style_check.json not present or unavailable"}
	status_hash['validator_macro_complete'] = false
end

#read in our static pe/pm json
staff_hash = Mcmlln::Tools.readjson(staff_file)
staff_defaults_hash = Mcmlln::Tools.readjson(staff_defaults_file)

#read in out contacts.json so we can update it with pe/pm:
if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
else
	contacts_hash = {}
	contacts_hash['submitter_email'] = 'workflows@macmillan.com'
	logger.info {"contacts json not found?"}
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

	#lookup mails & status for PE's and PM's, add to submitter_file json
	contacts_hash['production_manager_email'], status_hash['pm_lookup'] = staff_lookup('PM', pm_name, staff_hash, contacts_hash['submitter_email'], staff_defaults_hash)
	contacts_hash['production_manager_name'] = pm_name
	contacts_hash['production_editor_email'], status_hash['pe_lookup'] = staff_lookup('PE', pe_name, staff_hash, contacts_hash['submitter_email'], staff_defaults_hash)
	contacts_hash['production_editor_name'] = pe_name

	Vldtr::Tools.write_json(contacts_hash, Val::Files.contacts_file)
	logger.info {"retrieved info--  PM mail:\"#{contacts_hash['production_manager_email']}\", status: \'#{status_hash['pm_lookup']}\'.  PE mail:\"#{contacts_hash['production_editor_email']}\", status: \'#{status_hash['pe_lookup']}\'"}
else
	logger.info {"no book_info.json found, unable to retrieve pe/pm emails"}
	status_hash['pm_lookup'], status_hash['pe_lookup'] = 'no bookinfo_file', 'no bookinfo_file'
end


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

#emailing workflows if pe/pm json lookups failed
if (File.file?(Val::Files.bookinfo_file) && (status_hash['pm_lookup']=='not in json' || status_hash['pe_lookup']=='not in json'))
	logger.info {"pe or pm json lookup failed"}

	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "PE/PM lookup failed: #{Val::Paths.project_name} on #{Val::Doc.filename_split}"

PE or PM lookup againt staff json failed for bookmaker_validator:

PE name (from data-warehouse): #{pe_name}
PM name (from data-warehouse): #{pm_name}

All emails for PM or PE will be emailed to workflows instead, please update json and re-run file.
MESSAGE_END

	#now sending
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message, 'workflows@macmillan.com', '')
		logger.info {"sent email re failed lookup, now exiting validator_checker"}
	end
end
