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
if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
else
	logger.info {"contacts json not found?"}
end


#--------------------- RUN
if File.file?(Val::Files.status_file)				#get info from status.json
		status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
		# run validator macro or log err depending on criteria
		if !File.file?(Val::Files.bookinfo_file)
				logger.info {"skipping macro #{macro_name}, no bookinfo file"}
		elsif status_hash['msword_copyedit'] == false
				logger.info {"skipping macro #{macro_name}, paper-copyedit"}
		elsif status_hash['epub_format'] == false
				logger.info {"skipping macro #{macro_name}, no EPUB format epub edition (fixed layout)"}
		else
			if File.file?(Val::Files.contacts_file)
				#email PM to tell them validator is beginning:
				if contacts_hash['ebooksDept_submitter'] == true
						to_header = "#{contacts_hash['submitter_name']} <#{contacts_hash['submitter_email']}>"
						to_email = contacts_hash['submitter_email']
				else
						to_header = "#{contacts_hash['production_manager_name']} <#{contacts_hash['production_manager_email']}>"
						to_email = contacts_hash['production_manager_email']
				end
				body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'','',Val::Posts.bookinfo).gsub(/SUBMITTER/,contacts_hash['submitter_name'])
				message_C = <<MESSAGE_END_C
From: Workflows <workflows@macmillan.com>
To: #{to_header}
CC: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END_C
				unless File.file?(Val::Paths.testing_value_file)
					Vldtr::Tools.sendmail("#{message_C}",to_email,'workflows@macmillan.com')
				end
			end
			macro_output = Vldtr::Tools.run_macro(logger,macro_name) #where will this log?  do we care?
			logger.info {"output from run_macro.ps1: #{macro_output}"}
		end
else
		logger.info {"skipping macro #{macro_name}, no status.json file"}
end
