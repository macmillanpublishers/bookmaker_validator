require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup(Val::Posts.logfile_name,Val::Posts.logfolder)
logger = Val::Logs.logger

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
bot_success_txt = File.read(File.join(Val::Paths.mailer_dir,'bot_success.txt'))
error_notifyPM = File.read(File.join(Val::Paths.mailer_dir,'error_notifyPM.txt'))
# alerts_file = File.join(Val::Paths.mailer_dir,'warning-error_text.json')
# alert_hash = Mcmlln::Tools.readjson(alerts_file)

epub, epub_firstpass = '', ''
send_ok = true
errtxt_files = []
to_address = 'To: '


#--------------------- RUN
##find our epubs, check for error files in bookmaker
logger.info {"Verifying epub present..."}
if Dir.exist?(done_isbn_dir)
	Find.find(done_isbn_dir) { |file|
		if file =~ /_EPUBfirstpass.epub$/
			epub_firstpass = file
		elsif file !~ /_EPUBfirstpass.epub$/ && file =~ /_EPUB.epub$/
			epub = file
		end
	}
	if epub.empty? && epub_firstpass.empty?
		send_ok = false
		logger.info {"no epub exists! skip to the end :("}
	end
	logger.info {"checking for error files in bookmaker..."}
	Find.find(done_isbn_dir) { |file|
		if file =~ /ERROR.txt/
			logger.info {"error found in done_isbn_dir: #{file}. Adding it as an error for mailer"}
			file = file.match(/bookmaker_bot.*$/)[0]
			errtxt_files << file
			send_ok = false
		end
	}
else
	logger.info {"no done/isbn_dir exists! bookmaker must have an ISBN tied to a different workid! :("}
	send_ok = false
end


logger.info {"Reading in jsons from validator run"}
#get info from contacts.json
if File.file?(Val::Posts.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Posts.contacts_file)
	submitter_name = contacts_hash['submitter_name']
  submitter_mail = contacts_hash['submitter_email']
	pm_name = contacts_hash['production_manager_name']
	pm_mail = contacts_hash['production_manager_email']
	pe_name = contacts_hash['production_editor_name']
	pe_mail = contacts_hash['production_editor_email']
else
	send_ok = false
	logger.info {"Val::Posts.contacts_file.json not present or unavailable, unable to send mails"}
end

#get info from status.json, define status/errors & status/warnings
if File.file?(Val::Posts.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Posts.status_file)
	warnings = status_hash['warnings']
	errors = status_hash['errors']
	if !errtxt_files.empty?
    # log to alerts.json as error
    Vldtr::Tools.log_alert_to_json(alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["bookmaker_error"].gsub(/PROJECT/,Val::Paths.project_name)
		# bkmkrerr_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='bookmaker_error' then bkmkrerr_msg=h['message'].gsub(/PROJECT/,Val::Paths.project_name) end}}
		# errors = "ERROR(s):\n- #{bkmkrerr_msg} #{errtxt_files}"
		status_hash['errors'] = errors
		Vldtr::Tools.write_json(status_hash,Val::Posts.status_file)
		send_ok = false
	end
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end


#send a success notification email!
if send_ok
	logger.info {"everything checks out, sending email if we're not on staging :)"}
	if !warnings.empty?
		logger.info {"warnings were found; will be attached to the mailer at end of bookmaker run"}
	end
	unless File.file?(Val::Paths.testing_value_file)
		if contacts_hash['ebooksDept_submitter'] == true
        to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
        to_email = contacts_hash['submitter_email']
    else
        to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
        to_email = contacts_hash['production_manager_email']
    end
		body = Val::Resources.mailtext_gsubs(bot_success_txt, warnings, errors, Val::Posts.bookinfo)
		body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2')
		message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END
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
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message_b, 'workflows@macmillan.com', '')
		logger.info {"send_ok is FALSE, something's wrong"}
	end

	#sending a failure notice to PM
	if contacts_hash['ebooksDept_submitter'] == true
      to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
      to_email = contacts_hash['submitter_email']
  else
      to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
      to_email = contacts_hash['production_manager_email']
  end
	firstname = to_header.split(' ')[0]
	body = Val::Resources.mailtext_gsubs(error_notifyPM, warnings, errors, Val::Posts.bookinfo)
	body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2').gsub(/PMNAME/,firstname)
	message_d = <<MESSAGE_END_D
From: Workflows <workflows@macmillan.com>
To: #{to_header}
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_D
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message_d, to_email, 'workflows@macmillan.com')
		logger.info {"Sending epub error notification to PM"}
	end

end
