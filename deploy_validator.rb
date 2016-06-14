require 'fileutils'
require 'open3'
require 'process'
require 'json'

#--------------------- HEADER - main declarations
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
filename_normalized = filename_split.gsub(/[^[:alnum:]\._-]/,'')
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
logfolder = File.join('S:','resources','logs')
process_logfolder = File.join(logfolder,'processLogs')
json_logfile = File.join(logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.json")
human_logfile = File.join(logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.txt")
p_logfile = File.join(process_logfolder,"#{filename_normalized}-validator-plog_#{timestamp}.txt")
validator_dir = File.join('S:','resources','bookmaker_scripts','bookmaker_validator')

#------ local var names
ruby_exe = File.join('C:','Ruby200','bin','ruby.exe')
powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
process_watcher = File.join(validator_dir,'process_watcher.rb')
validator_tmparchive = File.join(validator_dir,'validator_tmparchive.rb')
run_Bookmaker_Validator = File.join(validator_dir,'run_Bookmaker_Validator.ps1')
validator_mailer = File.join(validator_dir,'validator_mailer.rb')
validator_cleanup = File.join(validator_dir,'validator_cleanup.rb')


#---------------------  FUNCTIONS  ####### method for calling other scritps, and merging and/or writing output to json.log
def write_json(hash, jsonlog)
	finaljson = JSON.pretty_generate(hash)
	File.open(jsonlog, 'w+:UTF-8') { |f| f.puts finaljson }
end
def update_json(newhash, currenthash, jsonlog)
	currenthash.merge!(newhash)
	write_json(currenthash,jsonlog)
end	
def log_time(currenthash,scriptname,txt,jsonlog)
	timestamp_colon = Time.now.strftime('%y%m%d_%H:%M:%S')
	time_hash = { "#{scriptname} #{txt}" => timestamp_colon }
	update_json(time_hash,currenthash,jsonlog)
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
	update_json(outputhash, hash, jsonlog)
	log_time(hash,scriptname,'completion time',jsonlog)	
end	


#--------------------- LOGGING
#create jsonlogfile 
output_hash = { 'completed' => false }
write_json(output_hash, json_logfile)


#--------------------- RUN
#launch process-watcher
log_time(output_hash,'process_watcher','start time',json_logfile)
pid = spawn("#{ruby_exe} #{process_watcher} \'#{input_file}\' #{timestamp}",[:out, :err]=>[p_logfile, "a"])		
Process.detach(pid)
log_time(output_hash,'process_watcher','completion time',json_logfile)


#the rest of the validator:
run_script("#{ruby_exe} #{validator_tmparchive} \'#{input_file}\'", output_hash, "validator_tmparchive", json_logfile)
run_script("#{powershell_exe} \"#{run_Bookmaker_Validator} \'#{input_file}\'\"", output_hash, "run_Bookmaker_Validator", json_logfile)
run_script("#{ruby_exe} #{validator_mailer} \'#{input_file}\'", output_hash, "validator_mailer", json_logfile)
run_script("#{ruby_exe} #{validator_cleanup} \'#{input_file}\'", output_hash, "validator_cleanup", json_logfile)

#mark the process done for process watcher
output_hash['completed'] = true
write_json(output_hash, json_logfile)

#generate some (more) human readable output
humanreadie = output_hash.map{|k,v| "#{k} = #{v}"}

File.open(human_logfile, 'w+:UTF-8') { |f| f.puts humanreadie }

