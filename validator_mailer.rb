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
notify_paper_copyedit = File.read(File.join(Val::Paths.mailer_dir,'notify_paper_copyedit.txt'))
notify_fixed_layout = File.read(File.join(Val::Paths.mailer_dir,'notify_fixed_layout.txt'))
error_notifyPM = File.read(File.join(Val::Paths.mailer_dir,'error_notifyPM.txt'))

cc_mails = ['workflows@macmillan.com']
cc_mails_b = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
# nogoodisbn = false
addPEcc = false 		#to cc PE's on isbn errors

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

#get alert string, alerts_hash
alerttxt_string, alerts_hash = Vldtr::Tools.get_alert_string(Val::Files.alerts_json)

#add errors/warnings to status.json
if alerts_hash.has_key?("error") then status_hash['errors'] = alerts_hash['error'] end
if alerts_hash.has_key?("warning") then status_hash['warnings'] = alerts_hash['warning'] end

#send error emails
if alerts_hash.has_key?("error") && send_ok
	unless File.file?(Val::Paths.testing_value_file)
		cc_address_err = cc_address
		cc_mails_err = cc_mails
		if status_hash['status'] == 'validator error'
    #send PM an error notification for validator errors
			if contacts_hash['ebooksDept_submitter'] == true
					to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
					to_email = contacts_hash['submitter_email']
			else
					to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
					to_email = contacts_hash['production_manager_email']
			end
			firstname = to_header.split(' ')[0]
			body = Val::Resources.mailtext_gsubs(error_notifyPM, alerttxt_string, Val::Posts.bookinfo)
			body = body.gsub(/PMNAME/,firstname)
			logger.info {"sending message to PE re: fatal validator errors encountered"}
		else
      #send submitter an error notification to submitter for errors prior to validator
			to_header = "#{submitter_name} <#{submitter_mail}>"
			to_email = contacts_hash['submitter_email']
			body = Val::Resources.mailtext_gsubs(error_text, alerttxt_string, Val::Posts.bookinfo)
			#add the PE to the email for isbn errors
			if status_hash['status'] == 'isbn error' && contacts_hash['ebooksDept_submitter'] != true
				cc_address_err = "#{cc_address}, #{pe_name} <#{pe_mail}>"
				cc_mails_err << pe_mail
			end
			logger.info {"sent message to submitter re: fatal isbn/doctype/password_protected errors encountered"}
		end
		message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{to_header}
#{cc_address_err}
#{body}
MESSAGE_END
		Vldtr::Tools.sendmail(message, to_email, cc_mails_err)
	end
end

#unstyled, no errors (not fixed layout or paper-copyedit), notification to PM for Westchester egalley.
if !alerts_hash.has_key?("error") && status_hash['document_styled'] == false && send_ok && status_hash['epub_format'] == true && status_hash['epub_format'] == true
		status_hash['status'] = 'Westchester egalley'
		unless File.file?(Val::Paths.testing_value_file)
		if contacts_hash['ebooksDept_submitter'] == true
				to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
				to_email = contacts_hash['submitter_email']
		else
				to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
				to_email = contacts_hash['production_manager_email']
		end
		body = Val::Resources.mailtext_gsubs(unstyled_notify, alerttxt_string, Val::Posts.bookinfo)
		message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_B
		Vldtr::Tools.sendmail(message_b, to_email, cc_mails)
		logger.info {"sent message to submitter cc pe/pm for notify/request for egalley to Westchester"}
	end
end

#paper_copyedit
if status_hash['msword_copyedit'] == false && send_ok && status_hash['epub_format'] == true
		status_hash['status'] = 'paper copyedit'
		if contacts_hash['ebooksDept_submitter'] == true
				to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
				to_email = contacts_hash['submitter_email']
		else
				to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
				to_email = contacts_hash['production_manager_email']
		end
		body = Val::Resources.mailtext_gsubs(notify_paper_copyedit, alerttxt_string, Val::Posts.bookinfo)
		message_c = <<MESSAGE_END_C
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_C
			unless File.file?(Val::Paths.testing_value_file)
				Vldtr::Tools.sendmail(message_c, to_email, 'workflows@macmillan.com')
				logger.info {"sent message to pm notifying them of paper_copyedit (no egalley)"}
		end
end

#fixed layout
if status_hash['epub_format'] == false && send_ok
		status_hash['status'] = 'fixed layout'
		if contacts_hash['ebooksDept_submitter'] == true
				to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
				to_email = contacts_hash['submitter_email']
		else
				to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
				to_email = contacts_hash['production_manager_email']
		end
		body = Val::Resources.mailtext_gsubs(notify_fixed_layout, alerttxt_string, Val::Posts.bookinfo)
		message_d = <<MESSAGE_END_D
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_D
		unless File.file?(Val::Paths.testing_value_file)
				Vldtr::Tools.sendmail(message_d, to_email, 'workflows@macmillan.com')
				logger.info {"sent message to pm notifying them of fixed_layout (no egalley)"}
		end
end

if !alerts_hash.has_key?("error") && status_hash['document_styled'] == true && send_ok
	logger.info {"this file looks bookmaker_ready, no mailer at this point"}
	if alerts_hash.has_key?("warning")
		logger.info {"warnings were found, no error ; warnings will be attached to the mailer at end of bookmaker run"}
	end
end

Vldtr::Tools.write_json(status_hash,Val::Files.status_file)

#emailing workflows if pe/pm json lookups failed
if (File.file?(Val::Files.bookinfo_file) && (status_hash['pm_lookup']=~/not in json|not in biblio and/ || status_hash['pe_lookup']=~/not in json|not in biblio and/))
	logger.info {"pe or pm json lookup failed"}

	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "PE/PM lookup failed: #{Val::Paths.project_name} on #{Val::Doc.filename_normalized}"

PE or PM lookup error occurred; Note lookup status below (and logs) for help

PE name (from data-warehouse): #{pe_name}
pe lookup 'status': #{status_hash['pe_lookup']}
PM name (from data-warehouse): #{pm_name}
pm lookup 'status': #{status_hash['pm_lookup']}

All emails for PM or PE will be emailed to workflows instead, please update json if needed and re-run file.
MESSAGE_END

	#now sending
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message, 'workflows@macmillan.com', '')
		logger.info {"sent email re failed lookup, now exiting validator_checker"}
	end
end
