require 'fileutils'
require 'logger'
require 'json'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'

# ---------------------- VARIABLES (HEADER)
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
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
mailer_dir = File.join(validator_dir,'mailer_messages')
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json') 
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
errFile = File.join(project_dir, "ERROR_RUNNING_#{filename_normalized}.txt")
thisscript = File.basename($0,'.rb')

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
err_notice = File.join(outbox,"ERROR--#{filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outbox,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
permalog = File.join(logfolder,'validator_history_report.json')


#--------------------- RUN
#load info from status.json
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
else
	status_hash[errors] = "Error occurred, validator failed: no status.json available"
	logger.info {"status.json not present or unavailable, creating error txt"}
end	

#let's move the original to outbox!
FileUtils.mv input_file, outbox

if !status_hash[errors].empty? || !status_hash[warnings].empty?
	if !status_hash[errors].empty? 
		#errors found!  use the text from mailer to write file:
		text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
		Mcmlln::Tools.overwriteFile(err_notice, text)
	elsif !status_hash[warnings].empty?
		#warnings found!  use the text from mailer to write file:
		text = status_hash[warnings]
		Mcmlln::Tools.overwriteFile(warn_notice, text)
		#let's move the done file to outbox
		File.rename(working_file, done_file)
		FileUtils.mv done_file, outbox
	end	
	#save the tmp_dir for review
	FileUtils.mv tmp_dir, "#{tmp_dir}__#{timestamp}"  #rename folder
	FileUtils.mv "#{tmp_dir}__#{timestamp}", logfolder 	
end	

if status_hash[errors].empty? && status_hash[warnings].empty?
	#let's move the done file to outbox
	File.rename(working_file, done_file)
	FileUtils.mv done_file, outbox
end	

if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
if File.file?(errFile) then FileUtils.rm inprogress_file end


#let's write to permalog!
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
else
	permalog_hash = []	
end	
if File.file?(contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(contacts_file)
end	
if File.file?(bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
end	
if File.file?(stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(stylecheck_file)
end	

index = permalog_hash.length + 1
permalog_hash[index]['file'] = filename_normalized
permalog_hash[index]['date'] = timestamp
permalog_hash[index]['isbn'] = bookinfo_file['isbn']
permalog_hash[index]['title'] = bookinfo_file['title']
permalog_hash[index]['submitter'] = contacts_hash['submitter_name']
permalog_hash[index]['styled?'] = stylecheck_hash['styled']
permalog_hash[index]['validator_completed?'] = stylecheck_hash['completed']
permalog_hash[index]['errors'] = status_hash['errors']
permalog_hash[index]['warnings'] = status_hash['warnings']


Vldtr::Tools.write_json(permalog_hash,permalog)



