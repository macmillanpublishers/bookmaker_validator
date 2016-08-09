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
alerts_file = File.join(Val::Paths.mailer_dir,'warning-error_text.json')
alert_hash = Mcmlln::Tools.readjson(alerts_file)

cc_mails = ['workflows@macmillan.com']
cc_mails_b = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
nogoodisbn = false
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


#Prepare warning/error text
warnings = "WARNINGS:\n"
if !status_hash['api_ok']
	api_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='api' then api_msg = h['message'] end}}
	warnings = "#{warnings}- #{api_msg}\n"
end
if status_hash['pm_lookup'] == 'not in biblio'
	pmlookup_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='pm_lookup_fail' then pmlookup_msg = h['message'] end}}
	warnings = "#{warnings}- #{pmlookup_msg}: \'#{contacts_hash['production_manager_name']}\'/\'#{contacts_hash['production_manager_email']}\' \n"
end
if status_hash['pe_lookup'] == 'not in biblio'
	pelookup_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='pe_lookup_fail' then pelookup_msg = h['message'] end}}
	warnings = "#{warnings}- #{pelookup_msg}: \'#{contacts_hash['production_editor_name']}\'/\'#{contacts_hash['production_editor_email']}\' \n"
end
if status_hash['filename_isbn']['isbn'].empty?
	nofileisbn_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='no_filename_isbn' then nofileisbn_msg = h['message'] end}}
	warnings = "#{warnings}- #{nofileisbn_msg}\n"
end
if !status_hash['filename_isbn']["checkdigit"]
	fileisbncd_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='filename_isbn_checkdigit_fail' then fileisbncd_msg = h['message'] end}}
	warnings = "#{warnings}- #{fileisbncd_msg} #{status_hash['filename_isbn']['isbn']}\n"
end
if !status_hash['filename_isbn_lookup_ok'] && status_hash['filename_isbn']["checkdigit"] == true
	fileisbnlookup_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='filename_isbn_lookup_fail' then fileisbnlookup_msg = h['message'] end}}
	warnings = "#{warnings}- #{fileisbnlookup_msg} #{status_hash['filename_isbn']['isbn']}\n"
end
if !status_hash['docisbn_checkdigit_fail'].empty?
	docisbncd_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='docisbn_checkdigit_fail' then docisbncd_msg = h['message'] end}}
	warnings = "#{warnings}- #{docisbncd_msg} #{status_hash['docisbn_checkdigit_fail'].uniq}\n"
end
if !status_hash['docisbn_lookup_fail'].empty?
	docisbnlookup_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='docisbn_lookup_fail' then docisbnlookup_msg = h['message'] end}}
	warnings = "#{warnings}- #{docisbnlookup_msg} #{status_hash['docisbn_lookup_fail'].uniq}\n"
end
if !status_hash['docisbn_match_fail'].empty? && status_hash['isbn_match_ok']
	docisbnmatch_msg=''; alert_hash['warnings'].each {|h| h.each {|k,v| if v=='docisbn_match_fail' then docisbnmatch_msg = h['message'] end}}
	warnings = "#{warnings}- #{docisbnmatch_msg} #{status_hash['docisbn_match_fail'].uniq}\n"
end
if warnings == "WARNINGS:\n"
	warnings = ''
end

#adding notices to Warnings for mailer & cleanup (only unstyled should be attached ot mailers
notices = "NOTICE(S):\n"
if !status_hash['document_styled']
	unstyled_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='unstyled' then unstyled_msg=h['message'] end}}
	notices = "#{notices}- #{unstyled_msg}\n"
end
if status_hash['epub_format'] == false
	fixlayout_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='fixed_layout' then fixlayout_msg=h['message'] end}}
	notices = "#{notices}- #{fixlayout_msg}\n"
end
if status_hash['msword_copyedit'] == false
	paprcopyedit_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='paper_copyedit' then paprcopyedit_msg=h['message'] end}}
	notices = "#{notices}- #{paprcopyedit_msg}\n"
end
if notices != "NOTICE(S):\n"
	new_warnings = "#{notices}#{status_hash['warnings']}"
	status_hash['warnings'] = new_warnings
end

#Errors
errheader_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='error_header' then errheader_msg=h['message'].gsub(/PROJECT/,Val::Paths.project_name) end}}
errors = "ERROR(s): #{errheader_msg}\n"
if !status_hash['isbn_match_ok']
	isbnmatch_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='isbn_match_fail' then isbnmatch_msg = h['message'] end}}
	errors = "#{errors}- #{isbnmatch_msg} #{status_hash['docisbns']}, #{status_hash['docisbn_match_fail']}.\n"
	addPEcc = true
end
if status_hash['docisbns'].empty? && !status_hash['filename_isbn_lookup_ok'] && status_hash['isbn_match_ok']
	nogoodisbn = true
end
if nogoodisbn
	nogoodisbn_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='no_good_isbn' then nogoodisbn_msg = h['message'] end}}
	errors = "#{errors}- #{nogoodisbn_msg}\n"
end
if !status_hash['validator_macro_complete'] && !nogoodisbn && status_hash['isbn_match_ok'] && status_hash['epub_format'] && status_hash['msword_copyedit']
	validatorerr_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='validator_error' then validatorerr_msg = h['message'].gsub(/PROJECT/,Val::Paths.project_name) end}}
	errors = "#{errors}- #{validatorerr_msg}\n"
	addPEcc = true
end
if !status_hash['docfile']
	#reset warnings & errors for a simpler message
	warnings, errors = '',"ERROR(s): #{errheader_msg}\n"
	docfileerr_msg=''; alert_hash['errors'].each {|h| h.each {|k,v| if v=='not_a_docfile' then docfileerr_msg = h['message'] end}}
	errors = "#{errors}- #{docfileerr_msg} \"#{Val::Doc.filename_normalized}\"\n"
end
if errors == "ERROR(s): #{errheader_msg}\n"
	errors = ''
end


#send submitter an error notification
if !errors.empty? && send_ok
	unless File.file?(Val::Paths.testing_value_file)
		to_address = "To: #{submitter_name} <#{submitter_mail}>"
		body = Val::Resources.mailtext_gsubs(error_text, warnings, errors, Val::Posts.bookinfo)
		cc_address_err = cc_address
		cc_mails_err = cc_mails
		if addPEcc
			cc_address_err = "#{cc_address}, #{pe_name} <#{pe_mail}>"
			cc_mails_err << pe_mail
		end
message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address_err}
#{body}
MESSAGE_END
		Vldtr::Tools.sendmail(message, submitter_mail, cc_mails_err)
		logger.info {"sent message to submitter re: fatal ERRORS encountered"}
	end
end

#unstyled, no errors (not fixed layout or paper-copyedit), notification to PM for Westchester egalley.
if errors.empty? && !status_hash['document_styled'] && send_ok && status_hash['epub_format'] == true && status_hash['epub_format'] == true
	unless File.file?(Val::Paths.testing_value_file)
		body = Val::Resources.mailtext_gsubs(unstyled_notify, warnings, errors, Val::Posts.bookinfo)
message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
To: #{pm_name} <#{pm_mail}>
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_B
		Vldtr::Tools.sendmail(message_b, pm_mail, cc_mails)
		logger.info {"sent message to submitter cc pe/pm for notify/request for egalley to Westchester"}
	end
end

#paper_copyedit
if status_hash['msword_copyedit'] == false && send_ok && status_hash['epub_format'] == true
		body = Val::Resources.mailtext_gsubs(notify_paper_copyedit, warnings, errors, Val::Posts.bookinfo)
message_c = <<MESSAGE_END_C
From: Workflows <workflows@macmillan.com>
To: #{pm_name} <#{pm_mail}>
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_C
			unless File.file?(Val::Paths.testing_value_file)
				Vldtr::Tools.sendmail(message_c, pm_mail, 'workflows@macmillan.com')
				logger.info {"sent message to pm notifying them of paper_copyedit (no egalley)"}
		end
end

#fixed layout
if status_hash['epub_format'] == false && send_ok
		body = Val::Resources.mailtext_gsubs(notify_fixed_layout, warnings, errors, Val::Posts.bookinfo)
message_d = <<MESSAGE_END_D
From: Workflows <workflows@macmillan.com>
To: #{pm_name} <#{pm_mail}>
Cc: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_D
		unless File.file?(Val::Paths.testing_value_file)
				Vldtr::Tools.sendmail(message_d, pm_mail, 'workflows@macmillan.com')
				logger.info {"sent message to pm notifying them of fixed_layout (no egalley)"}
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

#emailing workflows if pe/pm json lookups failed
if (File.file?(Val::Files.bookinfo_file) && (status_hash['pm_lookup']=~/not in json|not in biblio and/ || status_hash['pe_lookup']=~/not in json|not in biblio and/))
	logger.info {"pe or pm json lookup failed"}

	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: "PE/PM lookup failed: #{Val::Paths.project_name} on #{Val::Doc.filename_split}"

PE or PM lookup againt staff json failed for bookmaker_validator;
or submitter's email didn't match staff_emails.json;
or submitters division in staff_email.json doesn't match a division in defaults.json.
(or Dropbox API failed!)
See info below (and logs) for troubleshooting help

PE name (from data-warehouse): #{pe_name}
pe lookup 'status': #{status_hash['pe_lookup']}
PM name (from data-warehouse): #{pm_name}
pm lookup 'status': #{status_hash['pm_lookup']}

All emails for PM or PE will be emailed to workflows instead, please update json and re-run file.
MESSAGE_END

	#now sending
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message, 'workflows@macmillan.com', '')
		logger.info {"sent email re failed lookup, now exiting validator_checker"}
	end
end
