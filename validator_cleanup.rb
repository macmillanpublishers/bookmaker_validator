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
validator_dir = File.expand_path(File.dirname(__FILE__))
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
inprogress_file = File.join(project_dir,"#{filename_normalized}_IN_PROGRESS.txt")
err_notice = File.join(outbox,"ERROR--#{filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outbox,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
isbn = ''
permalog = File.join(logfolder,'validator_history_report.json')
permalogtxt = File.join(logfolder,'validator_history_report.txt')
#for now setting to outbox and creating folders
bookmaker_bot_folder = File.join(outbox, 'bookmaker_bot')
bookmaker_bot_IN = File.join(bookmaker_bot_folder, 'convert')
#bookmaker_bot_accessories = File.join(bookmaker_bot_folder, 'submitted_images')
FileUtils.mkdir_p bookmaker_bot_IN
#FileUtils.mkdir_p bookmaker_bot_accessories


#--------------------- RUN
#load info from jsons, start to dish info out to permalog as available, dump readable json into log
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
else
	permalog_hash = []	
end	
index = permalog_hash.length + 1
index = index.to_i
permalog_hash[index]={}
permalog_hash[index]['file'] = filename_normalized
permalog_hash[index]['date'] = timestamp
#puts "index is #{index}"

if File.file?(contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(contacts_file)
	permalog_hash[index]['submitter'] = contacts_hash['submitter_name']
	#dump json to logfile
	human_contacts = contacts_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}	
	logger.info {"dumping contents of contacts.json:"}
	File.open(logfile, 'a') { |f| f.puts human_contacts }
end	
if File.file?(bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
	permalog_hash[index]['isbn'] = bookinfo_hash['isbn']
	permalog_hash[index]['title'] = bookinfo_hash['title']	
	isbn = bookinfo_hash['isbn']
	#dump json to logfile
	human_bookinfo = bookinfo_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of bookinfo.json:"}
	File.open(logfile, 'a') { |f| f.puts human_bookinfo }
end
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
	permalog_hash[index]['errors'] = status_hash['errors']
	permalog_hash[index]['warnings'] = status_hash['warnings']
	#dump json to logfile
	human_status = status_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of status.json:"}
	File.open(logfile, 'a') { |f| f.puts human_status }
else
	status_hash[errors] = "Error occurred, validator failed: no status.json available"
	logger.info {"status.json not present or unavailable, creating error txt"}
end	
if File.file?(stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(stylecheck_file)
	permalog_hash[index]['styled?'] = stylecheck_hash['styled']
	permalog_hash[index]['validator_completed?'] = stylecheck_hash['completed']
end	
#write to json permalog!
#Vldtr::Tools.write_json(permalog_hash,permalog)
finaljson = JSON.pretty_generate(permalog_hash)
File.open(permalog, 'w+:UTF-8') { |f| f.puts finaljson }
#write permalog to text (& overwrite old text one!)
#human_permalog = permalog_hash.map{|k,v| "#{k} = #{v}"}
#File.open(permalogtxt, 'w') { |f| f.puts human_permalog }


#let's move the original to outbox!
FileUtils.mv input_file, outbox


#deal with errors & warnings!
if !status_hash['errors'].empty?
	#errors found!  use the text from mailer to write file:
	text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
	Mcmlln::Tools.overwriteFile(err_notice, text)
	#save the tmp_dir for review
	if Dir.exists?(tmp_dir)
		FileUtils.cp_r tmp_dir, "#{tmp_dir}__#{timestamp}"  #rename folder
		FileUtils.mv "#{tmp_dir}__#{timestamp}", logfolder 	
		logger.info {"errors found, writing err_notice, saving tmp_dir to logfolder"}
	else
		logger.info {"no tmpdir exists, this was probably not a .doc file"}
	end
end	
if !status_hash['warnings'].empty? && status_hash['errors'].empty?
	#warnings found!  use the text from mailer to write file:
	text = status_hash['warnings']
	Mcmlln::Tools.overwriteFile(warn_notice, text)
	logger.info {"warnings found, writing warn_notice"}
end	


#get ready for bookmaker to run on good docs!
if status_hash['bookmaker_ready']
	#add isbn to filename if its missing, and isbn available
	if filename_normalized !~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && !isbn.empty?
		tmp_dir_old = tmp_dir
		tmp_dir = tmp_dir.gsub(/$/,"#{isbn}")
		FileUtils.mv tmp_dir_old, tmp_dir
		working_file_old = File.join(tmp_dir, filename_normalized)
		working_file = working_file_old.gsub(/#{extension}$/,"#{isbn}#{extension}")
		done_file = working_file.gsub(/#{extension}$/,"_DONE#{extension}")
		File.rename(working_file_old, working_file)		
	end	
	File.rename(working_file, done_file)
	FileUtils.cp done_file, bookmaker_bot_IN
else	
	if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
end	


#cleanup
if File.file?(errFile) then FileUtils.rm errFile end
if File.file?(inprogress_file) then FileUtils.rm inprogress_file end








