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
status_hash = Val::Hashes.status_hash
status_hash['val_py_started'] = false

#--------------------- RUN
if !File.file?(Val::Files.status_file) || !File.file?(Val::Files.bookinfo_file)
	logger.info {"skipping script: #{py_script_name}, no bookinfo file or no status file"}
elsif status_hash["doctemplatetype"] != "sectionstart"
  logger.info {"skipping script: #{py_script_name}, doctemplatetype is not \"sectionsstart\""}
else
	unless File.file?(Val::Paths.testing_value_file)		#send a mail to PM that we're starting
		user_name, user_email = Vldtr::Tools.ebooks_mail_check()
		body = Val::Resources.mailtext_gsubs(notify_egalleymaker_begun,'',Val::Posts.bookinfo).gsub(/SUBMITTER/,Val::Hashes.contacts_hash['submitter_name'])
		message = Vldtr::Mailtexts.generic(user_name,user_email,"#{body}")
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
	if Val::Hashes.status_hash['typeset_from'].keys.include?("paper_copyedit")
		logger.info {"skipping script: #{py_script_name}, paper-copyedit"}
	elsif Val::Hashes.status_hash['epub_format'] == false
		logger.info {"skipping script: #{py_script_name}, no EPUB format epub edition (fixed layout)"}
  elsif Val::Hashes.status_hash['status'] == 'isbn error'
		logger.info {"skipping script: fatal isbn error"}
	else
    # log that we're beginning the python validator!
		status_hash['val_py_started'] = true
    #### run the python script
    ## versionA std logfile for stylecheck (only outputs items not already piped to v.py logfile):
		# py_output = Vldtr::Tools.runpython(py_script_path, "#{Val::Files.working_file}")
    ## versionB using shared logfile
		logfile_for_py = File.join(Val::Logs.logfolder, Val::Logs.logfilename)
    py_output = Vldtr::Tools.runpython(py_script_path, "#{Val::Files.working_file} \"#{logfile_for_py}\"")
    ## capture any random output from the runpython funciton call
		logger.info {"output from \"#{py_script_name}\": #{py_output}"}
	end
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
