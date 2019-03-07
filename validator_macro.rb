require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
notify_egalleymaker_begun = File.read(File.join(Val::Paths.mailer_dir,'notify_egalleymaker_begun.txt'))
macro_name="Validator.Launch"
macro_output=""
status_hash = Val::Hashes.status_hash
status_hash['val_macro_started'] = false

#--------------------- RUN
if !File.file?(Val::Files.status_file) || !File.file?(Val::Files.bookinfo_file)
	logger.info {"skipping macro #{macro_name}, no bookinfo file or no status file"}
elsif status_hash["doctemplatetype"] != "pre-sectionstart"
  logger.info {"skipping script: #{py_script_name}, doctemplatetype is not \"pre-sectionsstart\""}
else
	unless File.file?(Val::Paths.testing_value_file)		#send a mail to PM that we're starting
		user_name, user_email = Vldtr::Tools.ebooks_mail_check()
		body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'','',Val::Posts.bookinfo).gsub(/SUBMITTER/,Val::Hashes.contacts_hash['submitter_name'])
		message = Vldtr::Mailtexts.generic(user_name,user_email,"#{body}")
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
	if Val::Hashes.status_hash['msword_copyedit'] == false
		logger.info {"skipping macro #{macro_name}, paper-copyedit"}
	elsif Val::Hashes.status_hash['epub_format'] == false
		logger.info {"skipping macro #{macro_name}, no EPUB format epub edition (fixed layout)"}
	else
    begin
  		status_hash['val_macro_started'] = true
  		macro_output = Vldtr::Tools.run_macro(logger,macro_name) #run the macro
  		logger.info {"output from run_macro.ps1: #{macro_output}"}    
    ensure
      Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
    end
	end
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
