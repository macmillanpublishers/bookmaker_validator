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
validator_dir = File.expand_path(File.dirname(__FILE__))
working_dir = File.join('S:', 'validator_tmp')
mailer_dir = File.join(validator_dir,'mailer_messages')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
thisscript = File.basename($0,'.rb')

# ---------------------- LOGGING - has dependency on tmpdir!! - this stays the logfile if no tmp_dir is found
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
# these refer to bookmaker_bot/bookmaker_egalley now
bookmaker_project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-3].join(File::SEPARATOR)
bookmaker_project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-3].pop
project_done_dir = File.join(bookmaker_project_dir,'done')
done_isbn_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-1].join(File::SEPARATOR)
isbn = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-1].pop
epub = File.join(done_isbn_dir,"#{isbn}_EPUB.epub") 
epub_firstpass = epub = File.join(done_isbn_dir,"#{isbn}_EPUBfirstpass.epub")
#just for posts_cleanup.rb:
inprogress_file = File.join(bookmaker_project_dir,"#{filename_normalized}_IN_PROGRESS.txt")
warn_notice = File.join(outfolder,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
err_notice = File.join(outfolder,"ERROR--#{filename_normalized}--Validator_Failed.txt")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
permalog = File.join(logfolder,'validator_history_report.json')
permalogtxt = File.join(logfolder,'validator_history_report.txt')
coresource_dir = 'O:'
epub_created = true
if File.file?(testing_value_file)
	et_project_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','egalley_transmittal')
else
	et_project_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','egalley_transmittal_stg')
end
outfolder = File.join(et_project_dir,'OUT',basename_normalized)

# these are all relative to the found tmpdir 
tmp_dir = ''
Find.find(working_dir) { |dir|
	if dir =~ /to_bookmaker-#{infile_index}$/ && File.directory?(dir)
		tmp_dir = dir
	end
}
if !tmp_dir.empty?
	bookinfo_file = File.join(tmp_dir,'book_info.json')
	stylecheck_file = File.join(tmp_dir,'style_check.json') 
	contacts_file = File.join(tmp_dir,'contacts.json')
	status_file = File.join(tmp_dir,'status_info.json')
	#done_file = input file in tmpdir
	working_file = ''
	Find.find(tmp_dir) { |file|
	if file !~ /_DONE#{extension}$/ && extension =~ /.doc($|x$)/
		working_file = file
	end
	}
	logfile = File.join(logfolder, File.basename(working_file, ".*").gsub(/$/,'_log.txt'))
else
	send_ok = false
	logger.info {"cannot find tmp_dir! skip to the end :("}
end	



#--------------------- RUN
#create outfolder:
FileUtils.mkdir_p outfolder

#presumes epub is named properly, moves a copy to coresource
if !File.file?(epub) && !File.file?(epub_firstpass)
	epub_created = false
elsif File.file?(epub_firstpass) 
	FileUtils.cp epub_firstpass, coresource_dir
	logger.info {"copied epub_firstpass to coresource_dir"}
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
elsif File.file?(epub)
	File.rename(,epub_firstpass)
	FileUtils.cp epub_firstpass, coresource_dir
	logger.info {"renamed epub to epub_firstpass, copied to coresource_dir"}
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
end

#let's move the original to outbox!
FileUtils.mv input_file, outfolder	

#deal with errors & warnings!
if !status_hash['errors'].empty?
	#errors found!  use the text from mailer to write file:
	text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
	Mcmlln::Tools.overwriteFile(err_notice, text)
	logger.info {"errors found, writing err_notice"}
end	
if !status_hash['warnings'].empty? && status_hash['errors'].empty? && !status_hash['bookmaker_ready']
	#warnings found!  use the text from mailer to write file:
	text = status_hash['warnings']
	Mcmlln::Tools.overwriteFile(warn_notice, text)
	logger.info {"warnings found, writing warn_notice"}
end	

#update permalog
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
	permalog_hash['index']['bookmaker_ran'] = true
	permalog_hash['index']['epub_created'] = true	
	if !epub_created
		permalog_hash['index']['epub_created'] = false
	end
	#write to json permalog!
	finaljson = JSON.pretty_generate(permalog_hash)
	File.open(permalog, 'w+:UTF-8') { |f| f.puts finaljson }
end	
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
else
	logger.info {"status.json not present or unavailable!?"}
end	


#cleanup
if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
if File.file?(errFile) then FileUtils.rm errFile end
if File.file?(inprogress_file) then FileUtils.rm inprogress_file end

