require 'dropbox_sdk'
require 'json'
require 'net/smtp'
require 'logger'
require 'find'

# ---------------------- VARIABLES (HEADER)
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = filename_split.scan( /[^[:alnum:]\._-]/ ) { |badchar| filename_split=filename_split.tr(badchar,'') } #strip any chars but alphanumeric, plus these 3 .-_
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
submitter_file = File.join(tmp_dir,'submitter.json')
testing_value_file = File.join("C:", "staging.txt")
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
no_pm = false
no_pe = false


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
	else
		logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", writing to json"}

		#writing user info from Dropbox API to json
		datahash = {}	
		datahash.merge!(submitter_name: user_name)
		datahash.merge!(submitter_email: user_email)
		finaljson = JSON.generate(datahash)

		# Printing the final JSON object
		File.open(submitter_file, 'w+:UTF-8') do |f|
		  f.puts finaljson
		end
	end

	if File.file?(bookinfo_file)
		#get pm & pe emails:
		file_a = File.open(bookinfo_file, "r:utf-8")
		content_a = file_a.read
		file_a.close
		bookinfo_hash = JSON.parse(content_a)

		file_b = File.open(pe_pm_file, "r:utf-8")
		content_b = file_b.read
		file_b.close
		pe_pm_hash = JSON.parse(content_b) 

		pm_name = bookinfo_hash['production_manager'] 
		pe_name = bookinfo_hash['production_editor']
		logger.info('validator_mailer') {"retrieved from book_info.json- pe_name:\"#{pe_name}\", pm_name:\"#{pm_name}\""}	

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

		#setting up handling for cc's &/or submitter email is missing
		cc_emails = []
		cc_address= ''
		if user_email !~ /@/ 
			api_error = true
			user_email = 'workflows@macmillan.com'
			user_name = 'Workflows' 
		else
			cc_emails << 'workflows@macmillan.com' 
			cc_address = 'Cc: Workflows <workflows@macmillan.com>'		
		end
		if pm_email =~ /@/ 
			cc_emails << pm_email 
			cc_address = "#{cc_address}, #{pm_name} <#{pm_email}>"
		else 
			no_pm = true	
		end
		if pe_email =~ /@/ && pm_email != pe_email
			cc_emails << pe_email 
			cc_address = "#{cc_address}, #{pe_name} <#{pe_email}>"
		elsif pe_email !~ /@/
			no_pe = true	
		end
	else
		logger.info('validator_mailer') {"no book_info.json found, unable to retrieve pe/pm emails"}	
		no_pm = true
	end	

	#check for errlog in tmp_dir:
	Find.find(tmp_dir) { |file|
		if file != stylecheck_file && file != bookinfo_file && file != working_file && file != submitter_file
			logger.info('validator_mailer') {"error log found in tmpdir: #{file}"}
			errlog = true
		end
	}

	#set appropriate email text based on presence of /IN/errfile /tmpdir/errlog, or missing book_info.json
	body_c=''
	case 
	when File.file?(errFile)
		logger.info('validator_mailer') {"error log in project inbox, setting email text accordingly"}	
		subject="ERROR running #{project_name} on #{filename_split}"
		body_a="Unable to run #{project_name} on file \'#{filename_split}\': this file is not a .doc or .docx and could not be processed."
		body_b="\'#{filename_split}\' and the error notification can be found in the \'#{project_name}/IN\' Dropbox folder"	
	when errlog
		logger.info('validator_mailer') {"error log found in tmpdir, setting email text accordingly"}	
		subject="ERROR running #{project_name} on #{filename_split}"
		body_a="An error occurred while attempting to run #{project_name} on your file \'#{filename_split}\'."
		body_b="Your original file and accompanying error notice may now be found in the \'#{project_name}/OUT\' Dropbox folder."		
	when !File.file?(bookinfo_file)
		logger.info('validator_mailer') {"no book_info.json exists, data_warehouse lookup failed-- setting email text accordingly"}	
		subject="ERROR running #{project_name} on #{filename_split}"
		body_a="An error occurred while attempting to run #{project_name} on your file \'#{filename_split}\'."
		body_b="Book-info lookup failed: no book matching this ISBN was found during data-warehouse lookup."	
		body_c="Your original file and accompanying error notice are now in the \'#{project_name}/OUT\' Dropbox folder."
	else 
		logger.info('validator_mailer') {"No errors found, setting email text accordingly"}	
		subject="#{project_name} has completed for #{filename_normalized}"
		body_a="#{project_name} has finished running on file \'#{filename_normalized}\'."
		body_b="Your original document and the updated 'DONE' version may now be found in the \'#{project_name}/OUT\' Dropbox folder."	
	end		

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
#{cc_address}
Subject: #{subject}

#{body_a}

#{body_b}

#{body_c}
MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
	  Net::SMTP.start('10.249.0.12') do |smtp|
  	  smtp.send_message message, 'workflows@macmillan.com', 
	                              user_email, cc_emails
	  end
	end
	logger.info('validator_mailer') {"sent primary notification email, exiting email unless lookup failed"}	 
end	

#emailing workflows if one of our lookups failed
if no_pm || no_pe || api_error
	logger.info('validator_mailer') {"one of our lookups failed"}	 
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


