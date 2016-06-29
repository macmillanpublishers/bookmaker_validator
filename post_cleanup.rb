require 'fileutils'
require 'logger'
require 'json'
require 'find'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
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

# ---------------------- LOCAL VARIABLES
# these refer to the input file
lookup_isbn = basename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
index = basename_normalized.split('-').last
# these refer to bookmaker_bot/bookmaker_egalley
bookmaker_project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
bookmaker_project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
project_done_dir = File.join(bookmaker_project_dir,'done')
done_isbn_dir = File.join(project_done_dir, Metadata.pisbn)

# these are all relative to the found tmpdir 
tmp_dir = File.join(working_dir, "#{lookup_isbn}_to_bookmaker-#{index}")
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json') 
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json')
working_file, validator_infile_basename = '',''
Find.find(tmp_dir) { |file|
if file !~ /_DONE-#{index}#{extension}$/ && extension =~ /.doc($|x$)/
	if file =~ /_workingfile#{extension}$/
		working_file = file
	else
		validator_infile_basename = file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
	end
end
}

# ---------------------- LOGGING - has dependency on tmpdir!! - this stays the logfile if no tmp_dir is found
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, File.basename(working_file, ".*").gsub(/_workingfile$/,'_log.txt'))
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end

#just for posts_cleanup.rb:
epub = ''
epub_firstpass = ''
inprogress_file = File.join(bookmaker_project_dir,"#{filename_normalized}_IN_PROGRESS.txt")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
permalog = File.join(logfolder,'validator_history_report.json')
permalogtxt = File.join(logfolder,'validator_history_report.txt')
coresource_dir = 'O:'
epub_found = true
if File.file?(testing_value_file)
	et_project_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','egalley_transmittal_stg')
else
	et_project_dir = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)','egalley_transmittal')
end
outfolder = File.join(et_project_dir,'OUT',basename_normalized).gsub(/_DONE-#{index}$/,'')
warn_notice = File.join(outfolder,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
err_notice = File.join(outfolder,"ERROR--#{filename_normalized}--Validator_Failed.txt")
validator_infile = File.join(et_project_dir,'IN',validator_infile_basename)
errFile = File.join(et_project_dir, "ERROR_RUNNING_#{validator_infile_basename}#{extension}.txt")



#--------------------- RUN
# #get info from bookinfo.json so we can determine done_isbn_dir if its isbn doesn't match lookup_isbn
# if File.file?(bookinfo_file)
# 	bookinfo_hash = Mcmlln::Tools.readjson(bookinfo_file)
# 	alt_isbns = bookinfo_hash['alt_isbns']
# end	

# #find done_isbn_dir if bookmaker is using an alt isbn
# if !Dir.exist?(done_isbn_dir)
# 	logger.info {"expected done/isbn_dir does not exist, checking alt_isbns for our work_id to see what bookmaker used..."}
# 	dir_matches = []
# 	alt_isbns.each { |alt_isbn|
# 		testdir = File.join(project_done_dir, 'alt_isbn')
# 		if Dir.exist?(testdir)
# 			dir_matches << testdir
# 		end
# 	}
# 	if !dir_matches.empty?
# 		#if multiple matches, get the latest one
# 		done_isbn_dir = dir_matches.sort_by{ |d| File.mtime(d) }.pop
# 		logger.info {"found done/isbn/dir: \"#{done_isbn_dir}\""}
# 	else
# 		logger.info {"no done/isbn_dir exists! bookmaker must have an ISBN tied to a different workid! :("}
# 	end	
# end	

#find our epubs
if Dir.exist?(done_isbn_dir)
	Find.find(done_isbn_dir) { |file|
		if file =~ /_EPUBfirstpass.epub$/
			epub_firstpass = file
		elsif file !~ /_EPUBfirstpass.epub$/ && file =~ /_EPUB.epub$/
			epub = file
		end	
	}
end

#create outfolder:
FileUtils.mkdir_p outfolder

#presumes epub is named properly, moves a copy to coresource
if !File.file?(epub) && !File.file?(epub_firstpass)
	epub_found = false
elsif File.file?(epub_firstpass) 
	if !File.file?(testing_value_file)
		FileUtils.cp epub_firstpass, coresource_dir
		logger.info {"copied epub_firstpass to coresource_dir"}
	end	
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
elsif File.file?(epub)
	File.rename(epub, epub_firstpass)
	if !File.file?(testing_value_file)
		FileUtils.cp epub_firstpass, coresource_dir
		logger.info {"copied epub_firstpass to coresource_dir"}	
	end
	logger.info {"renamed epub to epub_firstpass, copied to coresource_dir"}
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
end

#let's move the original to outbox!
logger.info {"moving original file to outfolder.."}
FileUtils.mv validator_infile, outfolder	

#deal with errors & warnings!
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
	if !status_hash['errors'].empty?
		text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
		Mcmlln::Tools.overwriteFile(err_notice, text)
		logger.info {"errors found, writing err_notice"}
	end	
	if !status_hash['warnings'].empty? && status_hash['errors'].empty?
		text = status_hash['warnings']
		Mcmlln::Tools.overwriteFile(warn_notice, text)
		logger.info {"warnings found, writing warn_notice"}
	end	
else
	logger.info {"status.json not present or unavailable!?"}
end	

#update permalog
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
	permalog_hash[index]['bookmaker_ran'] = true
	permalog_hash[index]['epub_found'] = true	
	if !epub_found
		permalog_hash[index]['epub_found'] = false
	end
	#write to json permalog!
	finaljson = JSON.pretty_generate(permalog_hash)
	File.open(permalog, 'w+:UTF-8') { |f| f.puts finaljson }
end	


#cleanup
if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
if File.file?(errFile) then FileUtils.rm errFile end
if File.file?(inprogress_file) then FileUtils.rm inprogress_file end

