require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
notify_egalleymaker_begun = File.read(File.join(Val::Paths.mailer_dir,'notify_egalleymaker_begun.txt'))
section_styles_macro_name = "Validator.Launch"
pre_ss_macro_name = "Validator.Launch"
macro_output=""

#--------------------- RUN
# these files must be present to proceed
if !File.file?(Val::Files.status_file) || !File.file?(Val::Files.bookinfo_file)
	logger.info {"skipping validator macro, no bookinfo file or no status file"}
else
  #send a mail to PM that we're starting
	unless File.file?(Val::Paths.testing_value_file)
		user_name, user_email = Vldtr::Tools.ebooks_mail_check()
		body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'','',Val::Posts.bookinfo).gsub(/SUBMITTER/,Val::Hashes.contacts_hash['submitter_name'])
		message = Vldtr::Mailtexts.generic(user_name,user_email,"#{body}")
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
  # conditions under which we skip running the macro:
	if Val::Hashes.status_hash['msword_copyedit'] == false
		logger.info {"skipping validator macro, paper-copyedit"}
	elsif Val::Hashes.status_hash['epub_format'] == false
		logger.info {"skipping validator macro, no EPUB format epub edition (fixed layout)"}
	elsif Val::Hashes.status_hash['template_version'].nil?
    logger.info {"skipping validator macro, nil value found for template_version"}
  # choosing macro_name based on version template and proceeding to run
  else
    if Val::Hashes.status_hash['template_version'].empty?
      macro_name = pre_ss_macro_name
    else
      macro_name = section_styles_macro_name
    end
		logger.info {"based on template_version: \"#{Val::Hashes.status_hash['template_version']}\", running macro #{macro_name}"}
    #run the macro:
		macro_output = Vldtr::Tools.run_macro(logger,macro_name)
		logger.info {"output from run_macro.ps1: #{macro_output}"}
	end
end
