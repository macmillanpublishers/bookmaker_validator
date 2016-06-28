require 'fileutils'
require 'json'
require 'net/smtp'
require 'logger'
require 'find'
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
validator_dir = File.expand_path(File.dirname(__FILE__))
working_dir = File.join('S:', 'validator_tmp')
mailer_dir = File.join(validator_dir,'mailer_messages')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
thisscript = File.basename($0,'.rb')

# ---------------------- LOCAL VARIABLES
# these refer to bookmaker_bot/bookmaker_egalley now
bookmaker_project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
bookmaker_project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
project_done_dir = File.join(bookmaker_project_dir,'done')
isbn = basename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
index = basename_normalized.split('-').last.to_i
done_isbn_dir = File.join(project_done_dir, isbn)
epub = File.join(done_isbn_dir,"#{isbn}_EPUB.epub") 
epub_firstpass = epub = File.join(done_isbn_dir,"#{isbn}_EPUBfirstpass.epub")

# these are all relative to the found tmpdir 
tmp_dir = File.join(working_dir, "#{isbn}_to_bookmaker-#{index}")
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json') 
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json')
working_file, validator_infile_basename = '',''
Find.find(tmp_dir) { |file|
if file !~ /_DONE-#{index}#{extension}$/ && extension =~ /.doc($|x$)/
	if file =~ /_workingfile#{extension}$/
		working_file = file
	else
		validator_infile_basename = file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
	end
end
}

# ---------------------- LOGGING - has dependency on tmpdir!! - this stays the logfile if no tmp_dir is found
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, File.basename(working_file, ".*").gsub(/_workingfile$/,'_log.txt'))
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end

#just for posts_mailer.rb:
send_ok = true
errtxt_files = []
bot_success_txt = File.read(File.join(mailer_dir,'bot_success.txt'))
cc_mails = ['workflows@macmillan.com']
cc_address = 'Cc: Workflows <workflows@macmillan.com>'
to_address = 'To: '



#--------------------- RUN
logger.info {"Bookmaker has completed!  Verifying epub present:"}
#presumes epub is named properly
if Dir.exist?(done_isbn_dir)
	if !File.file?(epub) && !File.file?(epub_firstpass)
		send_ok = false
		logger.info {"no epub exists! skip to the end :("}
	end
	logger.info {"checking for error files in bookmaker?:"}
	Find.find(done_isbn_dir) { |file|
		if file =~ /ERROR.txt/
			logger.info {"error found in done_isbn_dir: #{file}. Adding it as an error for mailer"}
			file = file.gsub(//,'.txt')
			errtxt_files << file
			send_ok = false
		end
	}
else
	logger.info {"no done/isbn_dir exists! bookmaker must have found/used a different ISBN! :("}
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
	if !errtxt_files.empty?
		errors = "ERROR(s):\n-#{bookmaker_project_name} encountered non-fatal errors: #{errtxt_files}"
		status_hash['errors'] = errors
		Vldtr::Tools.write_json(status_hash,status_file)
		send_ok = false
	end	
else
	send_ok = false
	logger.info {"status.json not present or unavailable, unable to determine what to send"}
end	

#get info from bookinfo.json
if File.file?(bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
	work_id = bookinfo_hash['work_id']
	author = bookinfo_hash['author']
	title = bookinfo_hash['title']
	imprint = bookinfo_hash['imprint']
	product_type = bookinfo_hash['product_type']
	bookinfo_isbn = bookinfo_hash['isbn']
	bookinfo_pename = bookinfo_hash['production_editor']
	bookinfo_pmname = bookinfo_hash['production_manager']
	bookinfo="ISBN lookup for #{bookinfo_isbn}:\nTITLE: \"#{title}\", AUTHOR: \'#{author}\', IMPRINT: \'#{imprint}\', PRODUCT-TYPE: \'#{product_type}\'\n"
else
	send_ok = false
	logger.info {"bookinfo.json not present or unavailable, unable to determine what to send"}
end	


#send a success notification email!
if send_ok
	logger.info {"everything checks out, sending email if we're not on staging :)"}
	if !warnings.empty?
		logger.info {"warnings were found; will be attached to the mailer at end of bookmaker run"}
	end
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
		subject = "#{bookmaker_project_name} successfully processed #{filename_split}"
		body = bot_success_txt.gsub(/FILENAME_NORMALIZED/,working_file).gsub(/bookmaker_project_name/,bookmaker_project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		
message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
Subject: #{subject}

#{body}
MESSAGE_END

		Vldtr::Tools.sendmail(message, to_mail, cc_mails)
		logger.info {"Sending success message for validator to PE/PM"}	 		
	end	
else

	message_b = <<MESSAGE_END_B
From: Workflows <workflows@macmillan.com>
To: From: Workflows <workflows@macmillan.com>
Subject: validator_posts checks FAILED for #{filename_normalized} 

Either epub creation failed or other error detected during #{thisscript}
No notification email was sent to PE/PMs/submitter.

#{bookinfo}
#{errors}
#{warnings}
MESSAGE_END_B
	
	unless File.file?(testing_value_file)
		Vldtr::Tools.sendmail(message_b, 'workflows@macmillan.com', '')
		logger.info {"send_ok is FALSE, something's wrong"}
	end	
end	

