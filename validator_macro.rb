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

#--------------------- RUN
if !File.file?(Val::Files.status_file) || !File.file?(Val::Files.bookinfo_file)
	logger.info {"skipping macro #{macro_name}, no bookinfo file or no status file"}
else
	unless File.file?(Val::Paths.testing_value_file)
		user_name, user_email = Vldtr::Tools.ebooks_mail_check()
		body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'','',Val::Posts.bookinfo) #can I consolidate parameter ins to header even more now??
		message = Vldtr::Mailtexts.generic(user_name,user_email,"#{body}")
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
	if Val::Hashes.status_hash['msword_copyedit'] == false
		logger.info {"skipping macro #{macro_name}, paper-copyedit"}
	elsif Val::Hashes.status_hash['epub_format'] == false
		logger.info {"skipping macro #{macro_name}, no EPUB format epub edition (fixed layout)"}
	else
		macro_output = Vldtr::Tools.run_macro(logger,macro_name) #where will this log?  do we care?
		logger.info {"output from run_macro.ps1: #{macro_output}"}
	end
end
