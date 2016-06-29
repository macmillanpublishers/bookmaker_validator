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
outfolder = File.join(outbox,basename_normalized)
inprogress_file = File.join(project_dir,"#{filename_normalized}_IN_PROGRESS.txt")
err_notice = File.join(outfolder,"ERROR--#{filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outfolder,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
isbn = ''
permalog = File.join(logfolder,'validator_history_report.json')
permalogtxt = File.join(logfolder,'validator_history_report.txt')
if File.file?(testing_value_file)
	bot_egalleys_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','bookmaker_bot_stg','bookmaker_egalley')
else
	bot_egalleys_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','bookmaker_bot','bookmaker_egalley')
end
bookmaker_bot_IN = File.join(bot_egalleys_dir, 'convert')
#bookmaker_bot_accessories = File.join(bookmaker_bot_folder, 'submitted_images')


#--------------------- RUN
#load info from jsons, start to dish info out to permalog as available, dump readable json into log
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
else
	permalog_hash = {}	
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
	permalog_hash[index]['bookmaker_ready'] = status_hash['bookmaker_ready']	
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
finaljson = JSON.pretty_generate(permalog_hash)
File.open(permalog, 'w+:UTF-8') { |f| f.puts finaljson }


#deal with errors & warnings!
if !status_hash['errors'].empty?
	#create outfolder:
	FileUtils.mkdir_p outfolder
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
	#let's move the original to outbox!
	FileUtils.mv input_file, outfolder	
end	
if !status_hash['warnings'].empty? && status_hash['errors'].empty? && !status_hash['bookmaker_ready']
	#create outfolder:
	FileUtils.mkdir_p outfolder
	#warnings found!  use the text from mailer to write file:
	text = status_hash['warnings']
	Mcmlln::Tools.overwriteFile(warn_notice, text)
	logger.info {"warnings found, writing warn_notice"}
end	


#get ready for bookmaker to run on good docs!
if status_hash['bookmaker_ready']
	#change file & folder name to isbn if its available,keep a DONE file with orig filename
	if !isbn.empty?
		#rename tmp_dir so it doesn't get re-used and has index #
		tmp_dir_old = tmp_dir
		tmp_dir = File.join(working_dir,"#{isbn}_to_bookmaker-#{index}")
		FileUtils.mv tmp_dir_old, tmp_dir
		#make a copy of working file and give it a DONE in filename for troubleshooting from this folder
		working_file = File.join(tmp_dir, filename_normalized)
		done_file = working_file
		#setting up name for done_file: this needs to include working isbn, DONE, and index.  Here we go:
		if working_file =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    		isbn_condensed = working_file.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    		if isbn_condensed != isbn
    			done_file = working_file.gsub(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/,isbn)
    			logger.info {"filename isbn is != lookup isbn, editing filename (for done_file)"}
    		end
    	else	
    		logger.info {"adding isbn to done_filename because it was missing"}
			done_file = working_file.gsub(/#{extension}$/,"_#{isbn}#{extension}")
    	end	
    	done_file = done_file.gsub(/#{extension}$/,"_DONE-#{index}#{extension}")
		FileUtils.cp working_file, done_file
		FileUtils.cp done_file, bookmaker_bot_IN
		#rename working file to keep it distinct from infile
		new_workingfile = working_file.gsub(/#{extension}$/,"_workingfile#{extension}")
		File.rename(working_file, new_workingfile)
		#make a copy of infile so we have a reference to it for posts
		FileUtils.cp input_file, tmp_dir
	else
		logger.info {"for some reason, isbn is empty, can't do renames & moves :("}
	end	
else	
	if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
	if File.file?(errFile) then FileUtils.rm errFile end
	if File.file?(inprogress_file) then FileUtils.rm inprogress_file end	
end	
