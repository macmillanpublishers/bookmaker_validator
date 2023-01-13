require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

contacts_file = Val::Files.contacts_file
status_file = Val::Files.status_file
alerts_json = Val::Files.alerts_json

bot_success_txt = File.read(File.join(Val::Paths.mailer_dir,'bot_success.txt'))
error_notifyPM = File.read(File.join(Val::Paths.mailer_dir,'error_notifyPM.txt'))

send_ok = ''
to_address = 'To: '
doctemplatetype = ''

#--------------------- RUN

logger.info {"Reading in jsons from validator run"}
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

#get info from status.json, define status/errors & status/warnings
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
	upload_ok = status_hash['upload_ok']
	warnings = status_hash['warnings']
	errors = status_hash['errors']
  doctemplatetype = status_hash['doctemplatetype']
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end

alerttxt_string, alerts_hash = Vldtr::Tools.get_alert_string(alerts_json)

#send a success notification email!
if send_ok == true && upload_ok == true
	logger.info {"everything checks out, sending email if we're not on staging :)"}
	if !warnings.empty?
		logger.info {"warnings were found; will be attached to the mailer at end of bookmaker run"}
	end
  # prepare contacts_hash for submitter instead of PM, fo rebooks submitters &/or Staging server
	if contacts_hash['ebooksDept_submitter'] == true || File.file?(Val::Paths.testing_value_file)
		to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
		to_email = contacts_hash['submitter_email']
	else
		to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
		to_email = contacts_hash['production_manager_email']
	end
	body = Val::Resources.mailtext_gsubs(bot_success_txt, alerttxt_string, Val::Posts.bookinfo)
	body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2')
	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END
  if File.file?(Val::Paths.testing_value_file)
    message += "\n\nThis message sent from STAGING SERVER; typically to PM #{contacts_hash['production_manager_email']}, but in this case to submitter instead, for testing"
    Vldtr::Tools.sendmail(message, contacts_hash['submitter_email'], 'workflows@macmillan.com')
    logger.info {"Sending epub success message slated for PM, to submitter (we're on Staging server)"}
  else
    Vldtr::Tools.sendmail(message, to_email, 'workflows@macmillan.com')
    logger.info {"Sending epub success message to PM"}
  end

else

	#sending a failure email to Workflows
	message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: validator_posts checks FAILED for #{Val::Doc.filename_normalized}

Either epub creation failed or other error detected during #{Val::Resources.thisscript}
No notification email was sent to PE/PMs/submitter.

#{Val::Posts.bookinfo}
#{errors}
#{warnings}
MESSAGE_END_B
	if File.file?(Val::Paths.testing_value_file)
    message_b += "\n\nThis message sent from STAGING SERVER"
  end
		Vldtr::Tools.sendmail(message_b, 'workflows@macmillan.com', '')
		logger.info {"send_ok is FALSE, something's wrong"}

	#sending a failure notice to PM
  # prepare contacts_hash for submitter instead of PM, fo rebooks submitters &/or Staging server
	if contacts_hash['ebooksDept_submitter'] == true || File.file?(Val::Paths.testing_value_file)
		to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
		to_email = contacts_hash['submitter_email']
	else
		to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
		to_email = contacts_hash['production_manager_email']
	end
	firstname = to_header.split(' ')[0]
	body = Val::Resources.mailtext_gsubs(error_notifyPM, alerttxt_string, Val::Posts.bookinfo)
	body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2').gsub(/PMNAME/,firstname)
	message_d = <<MESSAGE_END_D
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_D
  if File.file?(Val::Paths.testing_value_file)
    message_d += "\n\nThis message sent from STAGING SERVER, would typically go to PM (#{contacts_hash['production_manager_email']}), instead to submitter for testing."
    Vldtr::Tools.sendmail(message_d, Val::Hashes.contacts_hash['submitter_email'], 'workflows@macmillan.com')
    logger.info {"Sending epub error message slated for PM, to submitter (we're on Staging server)"}
  else
		Vldtr::Tools.sendmail(message_d, to_email, 'workflows@macmillan.com')
		logger.info {"Sending epub error notification to PM"}
	end
end
