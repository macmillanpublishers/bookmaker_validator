require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DEFINITIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

send_ok = true
error_text = File.read(File.join(Val::Paths.mailer_dir,'error_occurred.txt'))
unstyled_notify = File.read(File.join(Val::Paths.mailer_dir,'unstyled_notify.txt'))
unstyled_request = File.read(File.join(Val::Paths.mailer_dir,'unstyled_request.txt'))
cc_mails = ['workflows@macmillan.com']
cc_mails_b = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
to_address = 'To: '
WC_name = 'Matthew Retzer'
WC_mail = 'matthew.retzer@macmillan.com'


#--------------------- RUN
#note in logs if we're on staging server:
if File.file?(Val::Paths.testing_value_file)
	logger.info {"looks like we're on staging, won't be sending mails"}
end

#get info from status.json, define status/errors & status/warnings
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
	status_hash['warnings'] = ''
	status_hash['errors'] = ''
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end

#get info from contacts.json
if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
	submitter_name = contacts_hash['submitter_name']
    submitter_mail = contacts_hash['submitter_email']
	pm_name = contacts_hash['production_manager_name']
	pm_mail = contacts_hash['production_manager_email']
	pe_name = contacts_hash['production_editor_name']
	pe_mail = contacts_hash['production_editor_email']
else
	send_ok = false
	logger.info {"Val::Files.contacts_file.json not present or unavailable, unable to send mails"}
end

#get info from bookinfo.json
if File.file?(Val::Files.bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(Val::Files.bookinfo_file)
	work_id = bookinfo_hash['work_id']
	author = bookinfo_hash['author']
	title = bookinfo_hash['title']
	imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']
	bookinfo_isbn = bookinfo_hash['isbn']
	bookinfo_pename = bookinfo_hash['production_editor']
	bookinfo_pmname = bookinfo_hash['production_manager']
	bookinfo="ISBN lookup for #{bookinfo_isbn}:\nTITLE: \"#{title}\"\nAUTHOR: \'#{author}\'\nIMPRINT: \'#{imprint}\'\nPRODUCT-TYPE: \'#{product_type}\'\n"
else
	logger.info {"bookinfo.json not present or unavailable, unable to determine what to send"}
end


#Prepare warning/error text
warnings = "WARNINGS:\n"
if !status_hash['api_ok']
	#warning-api
	warnings = "#{warnings}- Dropbox api cannot determine file submitter.\n"
end
if status_hash['filename_isbn']['isbn'].empty?
	#warning-no_filename_isbn
	warnings = "#{warnings}- No ISBN was included in the filename.\n"
end
if !status_hash['filename_isbn']["checkdigit"]
	#warning-filename_isbn_checkdigit_fail
	warnings = "#{warnings}- The ISBN included in the filename is not valid (#{status_hash['filename_isbn']['isbn']}): the checkdigit does not match. \n"
end
if !status_hash['filename_isbn_lookup_ok'] && status_hash['filename_isbn']["checkdigit"]
	warnings = "#{warnings}- Data-warehouse lookup of the ISBN included in the filename failed (#{status_hash['filename_isbn']['isbn']}).\n"
end
if !status_hash['docisbn_checkdigit_fail'].empty?
	#bad_isbns = status_hash['pisbn_checkdigit_fail'] + status_hash['docisbn_checkdigit_fail']
	warnings = "#{warnings}- ISBN(s) found in the manuscript are invalid; the check-digit does not match: #{status_hash['docisbn_checkdigit_fail'].uniq}\n"
end
if !status_hash['docisbn_lookup_fail'].empty?
	warnings = "#{warnings}- Data-warehouse lookup of ISBN(s) found in the manuscript failed: #{status_hash['docisbn_lookup_fail'].uniq}\n"
end
if !status_hash['docisbn_match_fail'].empty?
	warnings = "#{warnings}- ISBN(s) found in manuscript (#{status_hash['docisbn_match_fail'].uniq}) do not match the work-id of lookup ISBN (#{bookinfo_isbn}) and may be incorrect.\n"
end
if !status_hash['pm_lookup'] && File.file?(Val::Files.bookinfo_file)
	warnings = "#{warnings}- Error looking up Production Manager email for this title. Found PM_name/email: \'#{bookinfo_pmname}\'/\'#{contacts_hash['production_manager_email']}\' \n"
end
if !status_hash['pe_lookup'] && File.file?(Val::Files.bookinfo_file)
	warnings = "#{warnings}- Error looking up Production Editor email for this title. Found PE_name/email: \'#{bookinfo_pename}\'/\'#{contacts_hash['production_editor_email']}\' \n"
end
if !status_hash['document_styled']
	warnings = "#{warnings}- Document not styled with Macmillan styles.\n"
end
if warnings == "WARNINGS:\n"
	warnings = ''
end


errors = "ERROR(s): One or more problems prevented #{Val::Paths.project_name} from completing successfully:\n"
if !status_hash['isbn_match_ok']
	errors = "#{errors}- No usable ISBN present in the filename, and ISBNs in the manuscript were for different work-id's: #{status_hash['docisbns']}\n"
end
if status_hash['docisbns'].empty? && !status_hash['filename_isbn_lookup_ok'] && status_hash['isbn_match_ok']
	errors = "#{errors}- No usable ISBN present in the filename or in the manuscript.\n"
end
if !status_hash['validator_macro_complete']
	errors = "#{errors}- An error occurred while running #{Val::Paths.project_name}, please contact workflows@macmillan.com.\n"
end
if !status_hash['docfile']
	#reset warnings & errors for a simpler message
	warnings, errors = '',"ERROR(s): One or more problems prevented #{Val::Paths.project_name} from completing successfully:\n"
	errors = "#{errors}- The submitted document \"#{Val::Doc.filename_normalized}\" was not a .doc or .docx\n"
end
if errors == "ERROR(s): One or more problems prevented #{Val::Paths.project_name} from completing successfully:\n"
	errors = ''
end


#send submitter an error notification
if !errors.empty? && send_ok
	unless File.file?(Val::Paths.testing_value_file)
		to_address = "#{to_address}, #{submitter_name} <#{submitter_mail}>"
		body = Val::Resources.mailtext_gsubs(error_text, warnings, errors, bookinfo)

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
#{body}
MESSAGE_END

		Vldtr::Tools.sendmail(message, submitter_mail, cc_mails)
		logger.info {"sent message to submitter re: fatal ERRORS encountered"}
	end
end


if errors.empty? && !status_hash['document_styled'] && send_ok
	unless File.file?(Val::Paths.testing_value_file)
		#send email to westchester requesting firstpassepub cc: submitter, pe/pm
		to_address = "#{to_address}, #{WC_name} <#{WC_mail}>"
		if pm_mail =~ /@/
			cc_mails << pm_mail
			cc_mails_b << pm_mail
			cc_address = "#{cc_address}, #{pm_name} <#{pm_mail}>"
		end
		if pe_mail =~ /@/ && pe_mail != pm_mail
			cc_mails << pe_mail
			cc_mails_b << pe_mail
			cc_address = "#{cc_address}, #{pe_name} <#{pe_mail}>"
		end
		cc_mails << submitter_mail
		cc_address = "#{cc_address}, #{submitter_name} <#{submitter_mail}>"
		body = Val::Resources.mailtext_gsubs(unstyled_request, warnings, errors, bookinfo)

message_a = <<MESSAGE_END_A
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
#{body}
MESSAGE_END_A

		Vldtr::Tools.sendmail(message_a, WC_mail, cc_mails)
		logger.info {"sent message to westchester requesting firstpassepub for unstyled doc"}


		#send email to submitter cc:pe&pm to notify of success
		to_address = "To: #{submitter_name} <#{submitter_mail}>"
		cc_address = cc_address.gsub(/, #{submitter_name} <#{submitter_mail}>/,'')
		body = Val::Resources.mailtext_gsubs(unstyled_notify, warnings, errors, bookinfo)
		#remove unstyled warning from body:
		body = body.gsub(/- Document not styled with Macmillan styles.\n/,'')

message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
#{body}
MESSAGE_END_B

		Vldtr::Tools.sendmail(message_b, submitter_mail, cc_mails_b)
		logger.info {"sent message to submitter cc pe/pm notifying them of request to westchester for 1stpassepub"}
	end
end


if errors.empty? && status_hash['document_styled'] && send_ok
	logger.info {"this file looks bookmaker_ready, no mailer at this point"}
	if !warnings.empty?
		logger.info {"warnings were found, no error ; warnings will be attached to the mailer at end of bookmaker run"}
	end
end


#add errors/warnings to status.json for cleanup
if !errors.empty? then status_hash['errors'] = errors end
if !warnings.empty? then status_hash['warnings'] = warnings end

Vldtr::Tools.write_json(status_hash,Val::Files.status_file)
