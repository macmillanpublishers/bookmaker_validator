require 'fileutils'
require 'open3'
require 'process'
require 'json'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'

#--------------------- HEADER - main declarations
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
filename_normalized = filename_split.gsub(/[^[:alnum:]\._-]/,'')
basename_normalized = File.basename(filename_normalized, ".*")
extension = File.extname(filename_normalized)
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
tmp_dir=File.join(working_dir, basename_normalized)
validator_dir = File.dirname(__FILE__)
testing_value_file = File.join("C:", "staging.txt")
bookinfo_file = File.join(tmp_dir,'book_info.json')

# ---------------------- LOGGING VARIABLES
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt") 
deploy_logfolder = File.join('S:','resources','logs')
process_logfolder = File.join(deploy_logfolder,'processLogs')
json_logfile = File.join(deploy_logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.json")
human_logfile = File.join(deploy_logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.txt")
p_logfile = File.join(process_logfolder,"#{filename_normalized}-validator-plog_#{timestamp}.txt")

# ---------------------- LOCAL VARIABLES
ruby_exe = File.join('C:','Ruby200','bin','ruby.exe')
powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
process_watcher = File.join(validator_dir,'process_watcher.rb')
validator_tmparchive = File.join(validator_dir,'validator_tmparchive.rb')
run_macro = File.join(validator_dir,'run_macro.ps1')
macro_name="Validator.Launch"
validator_mailer = File.join(validator_dir,'validator_mailer.rb')
validator_cleanup = File.join(validator_dir,'validator_cleanup.rb')


#---------------------  FUNCTIONS  ####### method for calling other scritps, and merging and/or writing output to json.log
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


#--------------------- LOGGING
#create jsonlogfile 
output_hash = { 'completed' => false }
Vldtr::Tools.write_json(output_hash, json_logfile)


#--------------------- RUN
#launch process-watcher
log_time(output_hash,'process_watcher','start time',json_logfile)
pid = spawn("#{ruby_exe} #{process_watcher} \'#{input_file}\' #{timestamp}",[:out, :err]=>[p_logfile, "a"])		
Process.detach(pid)
log_time(output_hash,'process_watcher','completion time',json_logfile)


#the rest of the validator:
run_script("#{ruby_exe} #{validator_tmparchive} \'#{input_file}\'", output_hash, "validator_tmparchive", json_logfile)
if File.file?(bookinfo_file)
	run_script("#{powershell_exe} \"#{run_macro} \'#{input_file}\' \'#{macro_name}\' \'#{logfile}\'\"", output_hash, "run_macro", json_logfile)
else
	#log	
end
#check to see if we're ready to run bookmaker; read in status.json:
if File.file?(status_file) 
	status_hash = Mcmlln::Tools.readjson(status_file)
	if status_hash['bookmaker_ready']
		#RUN BOOKMAKER!
		puts "file is bookmaker ready! continuing"
	else
		puts "file is not bookmaker ready, continuing"
	end	
end

run_script("#{ruby_exe} #{validator_mailer} \'#{input_file}\'", output_hash, "validator_mailer", json_logfile)
run_script("#{ruby_exe} #{validator_cleanup} \'#{input_file}\'", output_hash, "validator_cleanup", json_logfile)

#mark the process done for process watcher
output_hash['completed'] = true
Vldtr::Tools.write_json(output_hash, json_logfile)

#generate some (more) human readable output
humanreadie = output_hash.map{|k,v| "#{k} = #{v}"}

File.open(human_logfile, 'w+:UTF-8') { |f| f.puts humanreadie }

