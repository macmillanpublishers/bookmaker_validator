require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
notify_egalleymaker_begun = File.read(File.join(Val::Paths.mailer_dir,'notify_egalleymaker_begun.txt'))
py_script_name = "validator_main.py"
py_script_path = File.join(Val::Paths.bookmaker_scripts_dir, 'sectionstart_converter', 'xml_docx_stylechecks', py_script_name)
# script_name="Validator.Launch"


#--------------------- RUN
if !File.file?(Val::Files.status_file) || !File.file?(Val::Files.bookinfo_file)
	logger.info {"skipping script: #{py_script_name}, no bookinfo file or no status file"}
else
	unless File.file?(Val::Paths.testing_value_file)		#send a mail to PM that we're starting
		user_name, user_email = Vldtr::Tools.ebooks_mail_check()
		body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'','',Val::Posts.bookinfo).gsub(/SUBMITTER/,Val::Hashes.contacts_hash['submitter_name'])
		message = Vldtr::Mailtexts.generic(user_name,user_email,"#{body}")
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
	if Val::Hashes.status_hash['msword_copyedit'] == false
		logger.info {"skipping script: #{py_script_name}, paper-copyedit"}
	elsif Val::Hashes.status_hash['epub_format'] == false
		logger.info {"skipping script: #{py_script_name}, no EPUB format epub edition (fixed layout)"}
  elsif Val::Hashes.status_hash['status'] == 'isbn error'
		logger.info {"skipping script: fatal isbn error"}
	else
    ## run the python script
    # version std logfile for stylecheck
		# py_output = Vldtr::Tools.runpython(py_script_path, "#{Val::Files.working_file}")
    # version with shared logfile
    py_output = Vldtr::Tools.runpython(py_script_path, "#{Val::Files.working_file} #{Val::Logs.logfilename}") #run the python script
    # capture any random output from the runpython funciton call
		logger.info {"output from \"#{py_script_name}\": #{py_output}"}
	end
end
