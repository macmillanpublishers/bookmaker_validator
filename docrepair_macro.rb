require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
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
		else
			#run macro
			Open3.popen2e("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro} \'#{Val::Files.working_file}\' \'#{macro_name}\' \'#{Val::Logs.std_logfile}\'\"") do |stdin, stdouterr, wait_thr|
					stdin.close
					stdouterr.each { |line|
							macro_output << line
					}
			end
			logger.info {"macro output: #{macro_output}"}
		end
else
		logger.info {"skipping macro #{macro_name}, no status.json file"}
end
