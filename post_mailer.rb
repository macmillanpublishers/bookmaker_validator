require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'



# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup(Val::Posts.logfile_name)
logger = Val::Logs.logger

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
bot_success_txt = File.read(File.join(Val::Paths.mailer_dir,'bot_success.txt'))
epubQA_request_txt = File.read(File.join(Val::Paths.mailer_dir,'epubQA_request.txt'))

epub, epub_firstpass = '', ''
send_ok = true
errtxt_files = []
cc_mails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
to_address = 'To: '



#--------------------- RUN
#get info from bookinfo.json so we can determine done_isbn_dir if its isbn doesn't match lookup_isbn
if File.file?(Val::Posts.bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(Val::Posts.bookinfo_file)
	work_id = bookinfo_hash['work_id']
	bookinfo_author = bookinfo_hash['author']
	bookinfo_title = bookinfo_hash['title']
	bookinfo_imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']
	bookinfo_isbn = bookinfo_hash['isbn']
	bookinfo_pename = bookinfo_hash['production_editor']
	bookinfo_pmname = bookinfo_hash['production_manager']
	bookinfo = "ISBN lookup for #{bookinfo_isbn}:\ntitle: \"#{bookinfo_title}\"\nauthor: \'#{bookinfo_author}\'\nimprint: \'#{bookinfo_imprint}\'\nproduct-type: \'#{product_type}\'\n"
else
	send_ok = false
	logger.info {"bookinfo.json not present or unavailable, unable to determine what to send"}
end

#find our epubs, check for error files in bookmaker
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
			file = file.gsub(//,'.txt')
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
		errors = "ERROR(s):\n-#{Val::Paths.project_name} encountered non-fatal errors: #{errtxt_files}"
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
		if pm_mail !~ /@/ && pe_mail !~ /@/ && submitter_mail =~ /@/
			to_address = "#{to_address}, #{submitter_name} <#{submitter_mail}>"
			to_mail = submitter_mail
		elsif pm_mail !~ /@/ && pe_mail !~ /@/ && submitter_mail !~ /@/
			to_address = cc_address
			to_mail = cc_mails
			cc_mails, cc_address = '', ''
		else
			cc_address = "#{cc_address}, #{submitter_name} <#{submitter_mail}>"
			to_mail = submitter_mail
		end
		body = Val::Resources.mailtext_gsubs(bot_success_txt, warnings, errors, bookinfo)

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
#{body}
MESSAGE_END

		Vldtr::Tools.sendmail(message, to_mail, cc_mails)
		logger.info {"Sending success message for validator to PE/PM"}

		#sending another email, for Patrick to QA epubs
		body_b = Val::Resources.mailtext_gsubs(epubQA_request_txt, warnings, errors, bookinfo)
	
message_epubQA = <<MESSAGE_END_C
From: Workflows <workflows@macmillan.com>
#{body_b}
MESSAGE_END_C

		unless Val::Resources.testing == true || Val::Resources.testing_Prod == true
			Vldtr::Tools.sendmail(message_epubQA, 'Patrick.Woodruff@macmillan.com', 'workflows@macmillan.com')
			logger.info {"Sending success message for validator to PE/PM"}
		end	

	end
else

	message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
To: From: Workflows <workflows@macmillan.com>
Subject: validator_posts checks FAILED for #{Val::Doc.filename_normalized}

Either epub creation failed or other error detected during #{Val::Resources.thisscript}
No notification email was sent to PE/PMs/submitter.

#{bookinfo}
#{errors}
#{warnings}
MESSAGE_END_B

	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message_b, 'workflows@macmillan.com', '')
		logger.info {"send_ok is FALSE, something's wrong"}
	end
end
