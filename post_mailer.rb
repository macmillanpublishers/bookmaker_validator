require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
# Dropbox back n forth from bookmaker, b/c it jumped folders and infile paths, required
# => recalculation of support files. For 'direct' runs products should share a temp folder so we should
# => be able to refer to previous definitions 
if Val::Doc.runtype == 'dropbox'
  Val::Logs.log_setup(Val::Posts.logfile_name,Val::Posts.logfolder)
  contacts_file = Val::Posts.contacts_file
  status_file = Val::Posts.status_file
  alerts_json = Val::Posts.alerts_json
else
  Val::Logs.log_setup()
  contacts_file = Val::Files.contacts_file
  status_file = Val::Files.status_file
  alerts_json = Val::Files.alerts_json
end

logger = Val::Logs.logger

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
bot_success_txt = File.read(File.join(Val::Paths.mailer_dir,'bot_success.txt'))
error_notifyPM = File.read(File.join(Val::Paths.mailer_dir,'error_notifyPM.txt'))
epubQA_request = File.read(File.join(Val::Paths.mailer_dir,'epubQA_request.txt'))
epubQA_request_rsuite = File.read(File.join(Val::Paths.mailer_dir,'epubQA_request-rsuite.txt'))

rsuiteQAaddress = File.read(File.join(Val::Resources.authkeys_repo,'rsuite-epub_QAaddress.txt')).strip
rsuiteQAdisplayname = File.read(File.join(Val::Resources.authkeys_repo,'rsuite-epub_QAdisplayname.txt')).strip

epub, epub_firstpass = '', ''
send_ok = true
errtxt_files = []
to_address = 'To: '
doctemplatetype = ''
epub_outputdir = ''
alertstring = ''

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
  if epub_firstpass.empty?  # << we used to accept final epubs here, but really that means a rename didn't go right in bookmaker_bot,
                            #   and now a non firstpass_epub will get screened at upload regardless. So we need to send an alert mailer here
    send_ok = false
  	if epub.empty?
      thiserrstring = "no epub found in bookmaker output."
    else
      thiserrstring = "epub created but not named '_firstpass', workflows-team review needed."
  	end
    alertstring = "#{Val::Hashes.alertmessages_hash['errors']['bookmaker_error']['message'].gsub(/PROJECT/,Val::Paths.project_name)} #{thiserrstring}"
    logger.warn {"#{thiserrstring}"}
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
	warnings = status_hash['warnings']
	errors = status_hash['errors']
  doctemplatetype = status_hash['doctemplatetype']
  epub_outputdir = Val::Hashes.epub_outputdir_hash[doctemplatetype]
	if !errtxt_files.empty?
		# log to alerts.json as error
		alertstring = "#{alertstring}\n#{Val::Hashes.alertmessages_hash['errors']['bookmaker_error']['message'].gsub(/PROJECT/,Val::Paths.project_name)} #{errtxt_files}"
		send_ok = false
	end
  unless alertstring.empty?
    Vldtr::Tools.log_alert_to_json(alerts_json, "error", alertstring)
		status_hash['errors'] = errors
		Vldtr::Tools.write_json(status_hash, status_file)
  end
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end

alerttxt_string, alerts_hash = Vldtr::Tools.get_alert_string(alerts_json)

#send a success notification email!
if send_ok
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

# # # # \/ temporarily disabling QA request send
# # # #   leaving commented but intact in case it's useful again later
#   # now, if epub needs QA,
#   #   we send a mail to workflows requesting QA!
#   if !File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true
#     if doctemplatetype == "sectionstart"
#   		body = Val::Resources.mailtext_gsubs(epubQA_request, alerttxt_string, Val::Posts.bookinfo)
#   		body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2').gsub(/DOCTEMPLATETYPE/,doctemplatetype).gsub(/OUTPUTFOLDER/,epub_outputdir).gsub(/EPUB_FILENAME/,File.basename(epub_firstpass))
#       if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true
#         body = "#{body}\n\n * * (TEST EMAIL SENT FROM STG SERVER) * *"
#       end
#   		message = <<MESSAGE_END
# From: Workflows <workflows@macmillan.com>
# To: Workflows <workflows@macmillan.com>
# #{body}
# MESSAGE_END
#   		Vldtr::Tools.sendmail(message, 'workflows@macmillan.com', '')
#   		logger.info {"Sending epub_QA request to Workflows b/c templatetype is \"sectionstart\""}
#     elsif doctemplatetype == "rsuite"
#       body = Val::Resources.mailtext_gsubs(epubQA_request_rsuite, alerttxt_string, Val::Posts.bookinfo)
#   		body = body.gsub(/(_DONE_[0-9]+)(.docx?)/,'\2').gsub(/DOCTEMPLATETYPE/,doctemplatetype).gsub(/OUTPUTFOLDER/,epub_outputdir).gsub(/EPUB_FILENAME/,File.basename(epub_firstpass))
#       if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true
#         body = "#{body}\n\n * * (TEST EMAIL SENT FROM STG SERVER) * *"
#       end
#       message = <<MESSAGE_END
# From: Workflows <workflows@macmillan.com>
# To: #{rsuiteQAdisplayname} <#{rsuiteQAaddress}>
# #{body}
# MESSAGE_END
#   		Vldtr::Tools.sendmail(message, rsuiteQAaddress, ['workflows@macmillan.com'])
#   		logger.info {"Sending epub_QA request to #{rsuiteQAdisplayname} from ebooks team b/c templatetype is \"rsuite\""}
#     end
#   end
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
    message += "\n\nThis message sent from STAGING SERVER"
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
    message += "\n\nThis message sent from STAGING SERVER, would typically go to PM (#{contacts_hash['production_manager_email']}), instead to submitter for testing."
    Vldtr::Tools.sendmail(message, Val::Hashes.contacts_hash['submitter_email'], 'workflows@macmillan.com')
    logger.info {"Sending epub error message slated for PM, to submitter (we're on Staging server)"}
  else
		Vldtr::Tools.sendmail(message_d, to_email, 'workflows@macmillan.com')
		logger.info {"Sending epub error notification to PM"}
	end
end
