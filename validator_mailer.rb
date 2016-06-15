ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

require 'dropbox_sdk'
require 'json'
require 'net/smtp'
require 'logger'
require 'find'
require 'oci8'
require 'to_xml'
require_relative '../utilities/oraclequery.rb'


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
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json')
submitter_file = File.join(tmp_dir,'contact_info.json')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
errFile = File.join(inbox, "ERROR_RUNNING_#{filename_normalized}.txt")

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
dropbox_filepath = File.join('/', project_name, 'IN', filename_split)
bookmaker_authkeys_dir = File.join(File.dirname(__FILE__), '../bookmaker_authkeys')
generated_access_token = File.read("#{bookmaker_authkeys_dir}/access_token.txt")
pe_pm_file = File.join('S:','resources','bookmaker_scripts','bookmaker_validator','staff_email.json')
errlog = false
api_error = false
contacts_datahash = {}	
no_pm = false
no_pe = false
stylecheck_complete = false 
stylecheck_styled = false
stylecheck_isbns = []
isbn_mismatch = false
to_email = 'workflows@macmillan.com'
to_name = 'Workflows' 


#--------------------- RUN
if filename_normalized =~ /^.*_IN_PROGRESS.txt/ || filename_normalized =~ /ERROR_RUNNING_.*.txt/
	logger.info('validator_mailer') {"this is a validator marker file, skipping (e.g. IN_PROGRESS or ERROR_RUNNING_)"}	
else
	#get Dropbox document 'modifier' via api
	client = DropboxClient.new(generated_access_token)
	root_metadata = client.metadata(dropbox_filepath)
	user_email = root_metadata["modifier"]["email"]
	user_name = root_metadata["modifier"]["display_name"]
	if root_metadata.nil? or root_metadata.empty? or !root_metadata or root_metadata['modifier'].nil? or root_metadata['modifier'].empty? or !root_metadata['modifier'] 
		logger.info('validator_mailer') {"dropbox api may have failed, not finding file metadata"}
		api_error = true
	else
		logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", writing to json"}
		
		#writing user info from Dropbox API to json
		contacts_datahash.merge!(submitter_name: user_name)
		contacts_datahash.merge!(submitter_email: user_email)
		finaljson = JSON.generate(contacts_datahash)
		# Printing the final JSON object
		if Dir.exist?(tmp_dir)
			File.open(submitter_file, 'w+:UTF-8') do |f|
			  f.puts finaljson
			end
		end	
	end
	
	#setting up handling for cc's and is submitter email is missing
	cc_emails = []
	cc_address= ''
	if user_email =~ /@/ 
		to_email = user_email
		to_name = user_name
		cc_emails << 'workflows@macmillan.com' 
		cc_address = 'Cc: Workflows <workflows@macmillan.com>'	
	else
		api_error = true
	end

	#get info from style_check.json
	if File.file?(stylecheck_file)
		file_c = File.open(stylecheck_file, "r:utf-8")
		content_c = file_c.read
		file_c.close
		stylecheck_hash = JSON.parse(content_c)
		stylecheck_complete = stylecheck_hash['completed']
		stylecheck_styled = stylecheck_hash['styled']['pass']
		stylecheck_isbns = stylecheck_hash['isbn']['list']
		logger.info('validator_mailer') {"retrieved from style_check.json- styled:\"#{stylecheck_styled}\", complete:\"#{stylecheck_complete}\", isbns:\"#{stylecheck_isbns}\""}
	else	
		logger.info('validator_mailer') {"style_check.json not present or unavailable"}
	end	
	
	if File.file?(bookinfo_file)
		#crosscheck isbns via work_id
		file_a = File.open(bookinfo_file, "r:utf-8")
		content_a = file_a.read
		file_a.close
		bookinfo_hash = JSON.parse(content_a)
		
		stylecheck_isbns.each { |sc_isbn| 
			if sc_isbn != bookinfo_hash['isbn']
				thissql_C = exactSearchSingleKey(sc_isbn, "EDITION_EAN")
				myhash_C = runPeopleQuery(thissql_C)
				if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book'] 
					logger.info('validator_mailer') {"isbn data-warehouse-lookup for manuscript isbn: #{sc_isbn} failed."}
					isbn_mismatch = true
					bookinfo_hash['isbn_mismatch'] = true
				else
					sc_work_id = myhash_C['book']['WORK_ID'][0]
					if sc_work_id != bookinfo_hash['work_id']
						bookinfo_hash['isbn_mismatch'] = true
						isbn_mismatch = true
						logger.info('validator_mailer') {"isbn mismatch found with manuscript isbn: #{sc_isbn}."}
					end
				end			
			end	
		}
		
		if isbn_mismatch == true
			finaljson = JSON.generate(bookinfo_hash)
			# Printing final JSON object
			File.open(bookinfo_file, 'w+:UTF-8') do |f|
				f.puts finaljson
			end
		end
		
		#get pm & pe emails, other book info:
		file_b = File.open(pe_pm_file, "r:utf-8")
		content_b = file_b.read
		file_b.close
		pe_pm_hash = JSON.parse(content_b) 

		pm_name = bookinfo_hash['production_manager'] 
		pe_name = bookinfo_hash['production_editor']
		logger.info('validator_mailer') {"retrieved from book_info.json- pe_name:\"#{pe_name}\", pm_name:\"#{pm_name}\""}	
		work_id = bookinfo_hash['work_id']
		author = bookinfo_hash['author']
		title = bookinfo_hash['title']
		imprint = bookinfo_hash['imprint']
		product_type = bookinfo_hash['product_type']
		
		pm_email = ''
		pe_email = ''
		for i in 0..pe_pm_hash.length - 1
			if pm_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
			 	pm_email = pe_pm_hash[i]['email']
			end
			if pe_name == "#{pe_pm_hash[i]['firstName']} #{pe_pm_hash[i]['lastName']}"
			 	pe_email = pe_pm_hash[i]['email']
			end		
		end	
		logger.info('validator_mailer') {"retrieved from staff_email.json- pe_email:\"#{pe_email}\", pm_email:\"#{pm_email}\""}	

		#further handling for cc's for PE's & PM's, also prep for adding to submitter_file json
		if pm_email =~ /@/ 
			cc_emails << pm_email 
			cc_address = "#{cc_address}, #{pm_name} <#{pm_email}>"
			contacts_datahash.merge!(production_manager_name: pm_name)
			contacts_datahash.merge!(production_manager_email: pm_email)			
		else 
			no_pm = true	
		end
		if pe_email =~ /@/ && pm_email != pe_email
			cc_emails << pe_email 
			cc_address = "#{cc_address}, #{pe_name} <#{pe_email}>"
			contacts_datahash.merge!(production_editor_name: pe_name)
			contacts_datahash.merge!(production_editor_email: pe_email)				
		elsif pe_email !~ /@/
			no_pe = true	
		end
		
		#add pe/pm emails (if found) to submitter_file
		if !no_pe || !no_pm
			#writing user info from Dropbox API to json		
			finaljson_B = JSON.generate(contacts_datahash)
			# Printing the final JSON object
			File.open(submitter_file, 'w+:UTF-8') do |f|
				f.puts finaljson_B
			end
		end
		
	else
		logger.info('validator_mailer') {"no book_info.json found, unable to retrieve pe/pm emails"}	
		no_pm = true
	end	
	
	#check for errlog in tmp_dir:
	if Dir.exist?(tmp_dir)
		Find.find(tmp_dir) { |file|
			if file != stylecheck_file && file != bookinfo_file && file != working_file && file != submitter_file && file != tmp_dir
				logger.info('validator_mailer') {"error log found in tmpdir: #{file}"}
				logger.info('validator_mailer') {"file: #{file}"}
				errlog = true
			end
		}
	end

	#set appropriate email text based on presence of /IN/errfile /tmpdir/errlog, or missing book_info.json
	subject="ERROR running #{project_name} on #{filename_split}"
	body_a="An error occurred while attempting to run #{project_name} on your file \'#{filename_split}\'."	
	body_c=''
	body_d=''
	body_bookinfo="--ISBN lookup:  TITLE: \"#{title}\", AUTHOR: \'#{author}\', IMPRINT: \'#{imprint}\', PRODUCT-TYPE: \'#{product_type}\')"
	body_a_complete="#{project_name} has finished running on file \'#{filename_normalized}\'."
	body_b_complete="Your original document and the updated 'DONE' version may now be found in the \'#{project_name}/OUT\' Dropbox folder."
	case 
	when File.file?(errFile)
		logger.info('validator_mailer') {"error log in project inbox, setting email text accordingly"}	
		body_a="Unable to run #{project_name} on file \'#{filename_split}\': either this file is not a .doc or .docx or the file's name does not contain an ISBN."
		body_b="\"#{filename_split}\" and accompanying error notification can be found in the \'#{project_name}/OUT\' Dropbox folder"	
	when errlog || !File.file?(stylecheck_file) || (File.file?(stylecheck_file) && !stylecheck_complete)
		logger.info('validator_mailer') {"error log found in tmpdir, or style_check.json completed value not true., setting email text accordingly"}	
		body_b="Your original file and accompanying error notice may now be found in the \'#{project_name}/OUT\' Dropbox folder."		
		body_c=body_bookinfo
	when !File.file?(bookinfo_file)
		logger.info('validator_mailer') {"no book_info.json exists, data_warehouse lookup failed-- setting email text accordingly"}	
		body_b="Book-info lookup failed: no book matching this ISBN was found during data-warehouse lookup."	
		body_c="Your original file and accompanying error notice are now in the \'#{project_name}/OUT\' Dropbox folder."
	when (File.file?(stylecheck_file) && !stylecheck_styled)
		logger.info('validator_mailer') {"document appears to be unstyled-- setting email text accordingly"}
		subject="#{project_name} determined #{filename_normalized} to be UNSTYLED"
		body_a="Unable to run #{project_name} on file \"#{filename_split}\": this document is not styled."
		body_b="Your original file has been moved to the \'#{project_name}/OUT\' Dropbox folder."
		body_c=body_bookinfo
		if isbn_mismatch
			body_d="Additional WARNING: the ISBN in your document's filename does not match one found in the manuscript."
		end		
	when isbn_mismatch
		logger.info('validator_mailer') {"the isbn from the filename and the isbn in the book do not match-- setting email text accordingly"}
	 	subject="#{project_name} completed for #{filename_normalized}, with warning"
	 	body_a=body_a_complete
	 	body_b=body_b_complete
		body_c=body_bookinfo
	 	body_d="WARNING: ISBN mismatch! : the ISBN in your document's filename does not match the one found in the manuscript."
	else 
		logger.info('validator_mailer') {"No errors found, setting email text accordingly"}	
		subject="#{project_name} completed for #{filename_normalized}"
		body_a=body_a_complete
		body_b=body_b_complete
		body_c=body_bookinfo	
	end		

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{to_name} <#{to_email}>
#{cc_address}
Subject: #{subject}

#{body_a}
#{body_b}

#{body_c}

#{body_d}
MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
	  Net::SMTP.start('10.249.0.12') do |smtp|
  	  smtp.send_message message, 'workflows@macmillan.com', 
	                              to_email, cc_emails
	  end
	end
	logger.info('validator_mailer') {"sent primary notification email, exiting mailer"}	 
end	

#emailing workflows if one of our lookups failed
if api_error || (File.file?(bookinfo_file) && (no_pm || no_pe))
	logger.info('validator_mailer') {"one (or more) of our lookups failed"}	 
	message_b = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "Lookup failed: #{project_name} on #{filename_split}"

One of our lookups failed for bookmaker_validator:

PE name (from data-warehouse): #{pe_name}
PM name (from data-warehouse): #{pm_name}
PE email (lookup against our static json): #{pe_email} 
PM email (lookup against our static json): #{pm_email}
submitter email (via dropbox api):  #{user_name}
submitter name (via dropbox api):  #{user_email}

*If the submitter email is missing, 'workflows' should have become primary addressee for standard mailer output, and pe/pm should have been cc'd
MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
	  Net::SMTP.start('10.249.0.12') do |smtp|
  	  smtp.send_message message_b, 'workflows@macmillan.com', 
	                              'workflows@macmillan.com'
	  end
	end
	logger.info('validator_mailer') {"sent email re failed lookup, now REALLY exiting mailer"}	 
end	


