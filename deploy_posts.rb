require 'fileutils'
require 'open3'
require 'process'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'

# ---------------------- LOCAL DECLARATIONS
if Val::Doc.runtype == 'dropbox'
  Val::Logs.log_setup(Val::Posts.logfile_name,Val::Posts.logfolder)
	json_logfile = Val::Posts.json_logfile
	process_logfile = Val::Posts.process_logfile
else
  Val::Logs.log_setup()
	json_logfile = Val::Logs.json_logfile
	process_logfile = Val::Logs.process_logfile
end
# init logging
logger = Val::Logs.logger

log_suffix = "POSTS_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"		#Note:  different for Posts.deploy
json_logfile = json_logfile.gsub(/.json$/,"#{log_suffix}.json")
output_hash = { 'completed' => false }
Vldtr::Tools.write_json(output_hash, json_logfile)   #create jsonlogfile

# ---------------------- Settings for this Deploy file
process_watcher = File.join(Val::Paths.scripts_dir,'process_watcher.rb')
post_mailer = File.join(Val::Paths.scripts_dir,'post_mailer.rb')
post_cleanup = File.join(Val::Paths.scripts_dir,'post_cleanup.rb')
post_cleanup_direct = File.join(Val::Paths.scripts_dir,'post_cleanup_direct.rb')
processwatch_sleep_min = 5


#--------------------- RUN
#launch process-watcher
Vldtr::Tools.log_time(output_hash,'process_watcher','start time',json_logfile)
pid = spawn("#{Val::Resources.ruby_exe} #{process_watcher} #{log_suffix} #{processwatch_sleep_min}",[:out, :err]=>[process_logfile, "w"])
Process.detach(pid)

#the rest of the validator:
begin
	popen_params = []
	for arg in ARGV
		popen_params.push("\'#{arg}\'")
	end
	Vldtr::Tools.run_script([Val::Resources.ruby_exe, post_mailer] + popen_params, output_hash, "post_mailer", json_logfile)
  if Val::Doc.runtype == 'direct'
    Vldtr::Tools.run_script([Val::Resources.ruby_exe, post_cleanup_direct] + popen_params, output_hash, "post_cleanup_direct", json_logfile)
  else
    Vldtr::Tools.run_script([Val::Resources.ruby_exe, post_cleanup] + popen_params, output_hash, "post_cleanup", json_logfile)
  end
  output_hash['completed'] = true		#mark the process done for process watcher
rescue Exception => e
	p e   #puts e.inspect
	puts "Something in deploy.rb scripts crashed, running rescue, attempting alertmail & kill process watcher"
	output_hash['validator_rescue_err'] = e
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(Vldtr::Mailtexts.deploy_err_text,'workflows@macmillan.com','')
		puts "sent alertmail"
	end
ensure
	kill_output = `taskkill /f /pid #{pid}`
	output_hash["pid #{pid} termination return"] = kill_output
	Vldtr::Tools.write_json(output_hash, json_logfile)
end
