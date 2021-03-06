require 'fileutils'
require 'open3'
require 'process'
require 'time'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'

# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
log_suffix = "_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
json_logfile = Val::Logs.json_logfile.gsub(/.json$/,"#{log_suffix}.json")
output_hash = { 'completed' => false }
Vldtr::Tools.write_json(output_hash, json_logfile)   #create jsonlogfile

# ---------------------- Settings for this Deploy file
process_watcher = File.join(Val::Paths.scripts_dir,'process_watcher.rb')
validator_tmparchive = File.join(Val::Paths.scripts_dir,'validator_tmparchive.rb')
validator_lookups = File.join(Val::Paths.scripts_dir,'validator_lookups.rb')
validator_py = File.join(Val::Paths.scripts_dir,'validator_py.rb')
validator_macro = File.join(Val::Paths.scripts_dir,'validator_macro.rb')
validator_checker = File.join(Val::Paths.scripts_dir,'validator_checker.rb')
validator_mailer = File.join(Val::Paths.scripts_dir,'validator_mailer.rb')
validator_cleanup = File.join(Val::Paths.scripts_dir,'validator_cleanup.rb')
validator_cleanup_direct = File.join(Val::Paths.scripts_dir,'validator_cleanup_direct.rb')
processwatch_sleep_min = 30

#--------------------- RUN
#launch process-watcher
Vldtr::Tools.log_time(output_hash,'process_watcher','start time',json_logfile)
pid = spawn("#{Val::Resources.ruby_exe} #{process_watcher} #{log_suffix} #{processwatch_sleep_min}",[:out, :err]=>[Val::Logs.process_logfile, "w"])
Process.detach(pid)

#the rest of the validator:
begin
	# collect args and prepare propogation of args to subscripts
	popen_params = []
	for arg in ARGV
		popen_params.push("\'#{arg}\'")
	end

	Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_tmparchive] + popen_params, output_hash, "validator_tmparchive", json_logfile)
	Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_lookups] + popen_params, output_hash, "validator_lookups", json_logfile)
	Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_py] + popen_params, output_hash, "validator_py", json_logfile)
  Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_macro] + popen_params, output_hash, "validator_macro", json_logfile)
	Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_checker] + popen_params, output_hash, "validator_checker", json_logfile)
	Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_mailer] + popen_params, output_hash, "validator_mailer", json_logfile)
  if Val::Doc.runtype == 'direct'
    Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_cleanup_direct] + popen_params, output_hash, "validator_cleanup_direct", json_logfile)
  else
    Vldtr::Tools.run_script([Val::Resources.ruby_exe, validator_cleanup] + popen_params, output_hash, "validator_cleanup", json_logfile)
  end

  # mark the process done for process watcher
	output_hash['completed'] = true
rescue Exception => e
	p e   #puts e.inspect
	puts "Something in deploy.rb scripts crashed, running rescue, attempting alertmail & kill process watcher"
	output_hash['validator_rescue_err'] = e
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(Vldtr::Mailtexts.deploy_err_text,'workflows@macmillan.com','')
		puts "sent alertmail"
	end
ensure
	if output_hash.key?('validator_cleanup completion time') && output_hash.key?('validator_tmparchive start time')
		timespent=((Time.parse(output_hash['validator_cleanup completion time'])-Time.parse(output_hash['validator_tmparchive start time'])).to_i/60).round(2)
		output_hash["minutes_elapsed"] = timespent
	end
	kill_output = `taskkill /f /pid #{pid}`
	output_hash["pid #{pid} termination return"] = kill_output
	Vldtr::Tools.write_json(output_hash, json_logfile)
end
