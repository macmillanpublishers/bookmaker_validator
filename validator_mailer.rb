require 'fileutils'
require 'json'
require 'net/smtp'
require 'logger'
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
thisscript = File.basename($0,'.rb')

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
send_ok = true
error_text = File.read(File.join(mailer_dir,'error_occurred.txt'))
unstyled_notify = File.read(File.join(mailer_dir,'unstyled_notify.txt'))
unstyled_request = File.read(File.join(mailer_dir,'unstyled_request.txt'))
validator_complete = File.read(File.join(mailer_dir,'validator_complete.txt'))
cc_mails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
to_address = 'To: '
WC_name = 'Matt Retzer'
WC_mail = 'matthew.retzer@macmillan.com'


#--------------------- RUN
#get info from status.json, define status/errors & status/warnings
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
	if (defined?(status_hash[errors])).nil? then status_hash[errors] = '' end
	if (defined?(status_hash[warnings])).nil? then status_hash[warnings] = '' end
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end	

#get info from contacts.json
if File.file?(contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(contacts_file)
	submitter_name = contacts_hash['submitter_name']
    submitter_mail = contacts_hash['submitter_email']
	pm_name = contacts_hash['production_manager_name']
	pm_mail = contacts_hash['production_manager_email']
	pe_name = contacts_hash['production_editor_name']
	pe_mail = contacts_hash['production_editor_email']
else
	send_ok = false
	logger.info {"contacts_file.json not present or unavailable, unable to send mails"}
end	

#get info from bookinfo.json
if File.file?(bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
	work_id = bookinfo_hash['work_id']
	author = bookinfo_hash['author']
	title = bookinfo_hash['title']
	imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']
	bookinfo="- ISBN lookup:  TITLE: \"#{title}\", AUTHOR: \'#{author}\', IMPRINT: \'#{imprint}\', PRODUCT-TYPE: \'#{product_type}\')"
else
	logger.info {"bookinfo.json not present or unavailable, unable to determine what to send"}
end	


#Prepare warning/error text
warnings = "WARNINGS:\n"
case 
when !status_hash['api_ok']		#condition 2:  dropbox api fails 
	warnings = "#{warnings}- Dropbox api cannot determine file submitter.\n"
when !status_hash['filename_isbn']["checkdigit"]  	#condition 3:  filename isbn bad checkdigit
	warnings = "#{warnings}- The ISBN included in the filename is not valid (#{status_hash['filename_isbn']['isbn']}): the checkdigit does not match. \n"
when !status_hash['isbn_lookup_ok']
	warnings = "#{warnings}- Data-warehouse lookup of the ISBN included in the filename failed (#{status_hash['filename_isbn']['isbn']}).\n"
when status_hash['filename_isbn']['isbn'].empty?
	warnings = "#{warnings}- No ISBN was included in the filename.\n"
when !status_hash['pisbn_checkdigit_fail'].empty? || !status_hash['docisbn_checkdigit_fail'].empty?
	bad_isbns = status_hash['pisbn_checkdigit_fail'] + status_hash['docisbn_checkdigit_fail']
	warnings = "#{warnings}- ISBN(s) found in the manuscript are invalid; the check-digit does not match: #{bad_isbns.uniq}\n"
when !status_hash['docisbn_lookup_fail'].empty?
	warnings = "#{warnings}- Data-warehouse lookup of ISBN(s) found in the manuscript failed: #{status_hash['docisbn_lookup_fail']}\n"
when !status_hash['docisbn_match_fail'].empty?
	warnings = "#{warnings}- ISBN(s) found in manuscript do not match the work-id of filename ISBN - they may be incorrect: #{status_hash['docisbn_match_fail']}\n"
when !status_hash['pm_lookup']
	warnings = "#{warnings}- Error looking up Production Manager info for this title. Found PM_name/email: \'#{contacts_hash['production_manager_name']}\'/\'#{contacts_hash['production_manager_email']}\' \n"
when !status_hash['pe_lookup']
	warnings = "#{warnings}- Error looking up Production Editor info for this title. Found PE_name/email: \'#{contacts_hash['production_editor_name']}\'/\'#{contacts_hash['production_editor_email']}\' \n"	
when !status_hash['document_styled']
	warnings = "#{warnings}- Document not styled with Macmillan styles.\n"
else 
	warnings = ''
end	


errors = "ERROR(s): One or more problems prevented #{project_name} from completing successfully:\n"
case
when !status_hash['docfile']
	errors = "#{errors}- The submitted document \"#{filename_normalized}\" was not a .doc or .docx\n"
when !status_hash['pisbns_match']
	errors = "#{errors}- No usable ISBN present in the filename, and ISBNs in the manuscript were for different work-id's: #{status_hash['pisbns']}\n"
when status_hash['pisbns'].length.empty? && (status_hash['filename_isbn']['isbn'].empty? || !status_hash['filename_isbn']["checkdigit"])
	errors = "#{errors}- No usable ISBN present in the filename or in the manuscript (for title info lookup)\n"
when !status_hash['pisbn_lookup_ok']
	errors = "#{errors}- No usable ISBN present in the filename, lookup from ISBN in manuscript (#{status_hash['pisbns']}) failed.\n"
when !status_hash['validator_run_ok']
	errors = "#{errors}- An error occurred while running #{project_name}, please contact workflows@macmillan.com.\n"
else
	errors = ''
end	

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
To: #{user_name} <#{user_mail}>
#{cc_address}
Subject: #{subject}

#{body}
MESSAGE_END

message_attachment = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
Subject: #{subject}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=#{marker}
--#{marker}
Content-Type: text/plain
Content-Transfer-Encoding:8bit
#{body}
--#{marker}
Content-Type: multipart/mixed; name=\"#{attachment}\"
Content-Transfer-Encoding:base64
Content-Disposition: attachment; filename="#{attachment}"
#{encodedcontent}
--#{marker}--
MESSAGE_END_B

#send submitter an error notification
if !errors.empty? && send_ok
	unless File.file?(testing_value_file)
		#prepare for attaching log: Read a file and encode it into base64 format for attaching
		attachment = logfile
		filecontent = File.read(attachment)
		encodedcontent = [filecontent].pack("m")   # base64
		marker = "zzzzzzzzzz"

		#address etc
		to_address = "#{to_address}, #{submitter_name} <#{submitter_email}>"
		subject = "ERROR running #{project_name} on #{filename_split}"
		body = error_text.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		Vldtr::Tools.sendmail(message_attachment, submitter_mail, cc_mails)
		logger.info {"sent message to submitter re: fatal ERRORS encountered"}	 		
	end	
end
	
if !status_hash['document_styled'] && send_ok
	unless File.file?(testing_value_file)
		#send email to westchester requesting firstpassepub cc: submitter, pe/pm
		to_address = "#{to_address}, #{WC_name} <#{WC_mail}>"
		if pm_mail =~ /@/ 
			cc_mails << pm_mail 
			cc_address = "#{cc_address}, #{pm_name} <#{pm_mail}>"
		end
		if pe_mail =~ /@/ && pe_mail != pm_mail
			cc_mails << pe_mail 
			cc_address = "#{cc_address}, #{pe_name} <#{pe_mail}>"
		end
		cc_mails << submitter_mail
		cc_address = "#{cc_address}, #{submitter_name} <#{submitter_mail}>"
		subject = "Request for First-pass epub for #{filename_split}"
		body = unstyled_request.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		Vldtr::Tools.sendmail(message, WC_mail, cc_mails)
		logger.info {"sent message to westchester requesting firstpassepub for unstyled doc"}


		#send email to submitter cc:pe&pm to notify of success
		to_address = "To: #{submitter_name} <#{submitter_email}>"
		cc_mails = cc_mails - submitter_mail
		cc_address = cc_address.gsub(/, #{submitter_name} <#{submitter_mail}>/,'')
		subject = "Notification of First-pass epub request for #{filename_split}"
		body = unstyled_notify.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		#remove unstyled warning from body:
		body = body.gsub(/- Document not styled with Macmillan styles.\n/,'')
		Vldtr::Tools.sendmail(message, submitter_mail, cc_mails)
		logger.info {"sent message to submitter cc pe/pm notifying them of request to westchester for 1stpassepub"}	 		
	end	
end

#this is a placeholder, eventually we won't do this until/unless bookmaker has run.. 
#or maybe we'll have two, one for bookmaker success, one for bookmaker failure
#are we attaching errors or logs?  not necessary if we consolidate logs in one place

if errors.empty && status_hash['document_styled'] && send_ok
	unless File.file?(testing_value_file)
		#conditional to addressees are complicated: 
		#However to & cc_mails passed to sendmail are ALL just 'recipients', the true to versus cc is sorted from the message header
		if pm_mail =~ /@/ 
			cc_mails << pm_mail 
			to_address = "#{to_address}, #{pm_name} <#{pm_mail}>"
		end
		if pe_mail =~ /@/ && pe_mail != pm_mail
			cc_mails << pe_mail 
			to_address = "#{to_address}, #{pe_name} <#{pe_mail}>"
		end
		if pm_mail !~ /@/ && pe_mail !~ /@/
			to_address = "#{to_address}, #{submitter_name} <#{submitter_mail}>"
		else
			cc_address = "#{cc_address}, #{submitter_name} <#{submitter_mail}>"
		end	
		subject = "#{project_name} successfully processed #{filename_split}"
		body = validator_complete.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		Vldtr::Tools.sendmail(message, submitter_mail, cc_mails)
		logger.info {"Sending success message for validator to PE/PM"}	 		
	end	
end	


#add errors/warnings to status.json for cleanup
if !errors.empty? then status_hash[errors] = errors end
if !warnings.empty? then status_hash[warnings] = warnings end

Vldtr::Tools.write_json(status_hash,status_file)








