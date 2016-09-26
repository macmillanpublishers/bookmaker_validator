require 'fileutils'
require 'open3'
require 'process'
require 'time'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
std_logfile = "#{Val::Logs.logfolder}/#{Val::Logs.logfilename}"
log_suffix = "_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
json_logfile = Val::Logs.json_logfile.gsub(/.json$/,"#{log_suffix}.json")
human_logfile = Val::Logs.human_logfile.gsub(/.txt$/,"#{log_suffix}.txt")
p_logfile = Val::Logs.p_logfile.gsub(/.txt$/,"#{log_suffix}.txt")

process_watcher = File.join(Val::Paths.scripts_dir,'process_watcher.rb')
validator_tmparchive = File.join(Val::Paths.scripts_dir,'validator_tmparchive.rb')
validator_lookups = File.join(Val::Paths.scripts_dir,'validator_lookups.rb')
validator_checker = File.join(Val::Paths.scripts_dir,'validator_checker.rb')
validator_mailer = File.join(Val::Paths.scripts_dir,'validator_mailer.rb')
validator_cleanup = File.join(Val::Paths.scripts_dir,'validator_cleanup.rb')
macro_name="Validator.Launch"

processwatch_sleep_min = 30

#---------------------  FUNCTIONS & message template
def log_time(currenthash,scriptname,txt,jsonlog)
	timestamp_colon = Time.now.strftime('%y%m%d_%H:%M:%S')
	time_hash = { "#{scriptname} #{txt}" => timestamp_colon }
	Vldtr::Tools.update_json(time_hash,currenthash,jsonlog)
end
def run_script(command,hash,scriptname,jsonlog)
	log_time(hash,scriptname,'start time',jsonlog)
	alloutput = ''
	Open3.popen2e(command) do |stdin, stdouterr, wait_thr|
	stdin.close
	stdouterr.each { |line|
		alloutput << line
		}
	end
	outputhash={ "#{scriptname}" => alloutput }
	Vldtr::Tools.update_json(outputhash, hash, jsonlog)
	log_time(hash,scriptname,'completion time',jsonlog)
end

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ALERT: #{Val::Paths.project_name} process crashed

#{Val::Resources.thisscript}.rb has crashed during #{Val::Paths.project_name} run.

Please see the following logfiles for assistance in troubleshooting:
#{std_logfile}
#{human_logfile}
#{p_logfile}

MESSAGE_END


#--------------------- LOGGING
#create jsonlogfile
output_hash = { 'completed' => false }
Vldtr::Tools.write_json(output_hash, json_logfile)


#--------------------- RUN
if !Val::Doc.filenametest.empty?
		output_hash['bad_filename'] = Val::Doc.filenametest
end
#launch process-watcher
log_time(output_hash,'process_watcher','start time',json_logfile)
pid = spawn("#{Val::Resources.ruby_exe} #{process_watcher} \'#{Val::Doc.input_file}\' #{log_suffix} #{processwatch_sleep_min}",[:out, :err]=>[p_logfile, "a"])
Process.detach(pid)

#the rest of the validator:
begin
	run_script("#{Val::Resources.ruby_exe} #{validator_tmparchive} \'#{Val::Doc.input_file}\'", output_hash, "validator_tmparchive", json_logfile)
	run_script("#{Val::Resources.ruby_exe} #{validator_lookups} \'#{Val::Doc.input_file}\'", output_hash, "validator_lookups", json_logfile)

	#now we make sure the macro needs to be run:
	if File.file?(Val::Files.status_file)				#get info from status.json
			status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
			# run validator macro or log err depending on criteria
			if !File.file?(Val::Files.bookinfo_file)
					output_hash['Val::Files.bookinfo_file'] = false ; output_hash['deploy.rb'] = 'skipping macro, no bookinfo file'
			elsif status_hash['msword_copyedit'] == false
					output_hash['msword_copyedit'] = false ; output_hash['deploy.rb'] = 'skipping macro, paper-copyedit'
			elsif status_hash['epub_format'] == false
					output_hash['epub_format'] = false ; output_hash['deploy.rb'] = 'skipping macro, no EPUB format epub edition'
			else
					run_script("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro} \'#{Val::Doc.input_file}\' \'#{macro_name}\' \'#{std_logfile}\'\"", output_hash, "Val::Resources.run_macro", json_logfile)
			end
	else
			output_hash['Val::Files.bookinfo_file'] = false ; output_hash['deploy.rb'] = 'skipping macro, no status.json file'
	end

	run_script("#{Val::Resources.ruby_exe} #{validator_checker} \'#{Val::Doc.input_file}\'", output_hash, "validator_checker", json_logfile)
	run_script("#{Val::Resources.ruby_exe} #{validator_mailer} \'#{Val::Doc.input_file}\'", output_hash, "validator_mailer", json_logfile)
	run_script("#{Val::Resources.ruby_exe} #{validator_cleanup} \'#{Val::Doc.input_file}\'", output_hash, "validator_cleanup", json_logfile)
	#mark the process done for process watcher
	output_hash['completed'] = true
rescue Exception => e
	p e   #puts e.inspect
	puts "Something in deploy.rb scripts crashed, running rescue, attempting alertmail & kill process watcher"
	output_hash['validator_rescue_err'] = e
	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message,'workflows@macmillan.com','')
		puts "sent alertmail"
	end
ensure
	if output_hash.key?('validator_cleanup completion time') && output_hash.key?('validator_tmparchive start time')
		timespent=((Time.parse(output_hash['validator_cleanup completion time'])-Time.parse(output_hash['validator_tmparchive start time'])).to_i/60).round(2)
		output_hash["minutes_elapsed"] = timespent
	end
	#process.kill apparently is inconsistent on windows:  trying shell "taskkill" instead:
	#https://blog.simplificator.com/2016/01/18/how-to-kill-processes-on-windows-using-ruby/
	kill_output = `taskkill /f /pid #{pid}`
	output_hash["pid #{pid} termination return"] = kill_output
	Vldtr::Tools.write_json(output_hash, json_logfile)
	#generate some (more) human readable output
	humanreadie = output_hash.map{|k,v| "#{k} = #{v}"}
	File.open(human_logfile, 'w+:UTF-8') { |f| f.puts humanreadie }
end
