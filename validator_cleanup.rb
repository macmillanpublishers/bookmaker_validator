require 'fileutils'
require 'logger'
require 'find'
require 'json'

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
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json')
submitter_file = File.join(tmp_dir,'contact_info.json')
testing_value_file = File.join("C:", "staging.txt")
inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
errFile = File.join(inbox, "ERROR_RUNNING_#{filename_normalized}.txt")

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end

# ---------------------- LOCAL VARIABLES
err_notice = File.join(outbox,"ERROR--#{filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outbox,"WARNING--#{filename_normalized}--validator_completed_with_warnings.txt")
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
errlog = false
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
stylecheck_complete = false 
stylecheck_styled = false
isbn_mismatch = false


#--------------------- RUN
#load info from syle_check.json
if File.file?(stylecheck_file)
	file_c = File.open(stylecheck_file, "r:utf-8")
	content_c = file_c.read
	file_c.close
	stylecheck_hash = JSON.parse(content_c)
	stylecheck_complete = stylecheck_hash['completed']
	stylecheck_styled = stylecheck_hash['styled']['pass']	
end

#check for isbn_mismatch
if File.file?(stylecheck_file)
	file_a = File.open(bookinfo_file, "r:utf-8")
	content_a = file_a.read
	file_a.close
	bookinfo_hash = JSON.parse(content_a)
	isbn_mismatch = bookinfo_hash["isbn_mismatch"]
end

#check for errlog in tmp_dir:
if Dir.exist?(tmp_dir)
	Find.find(tmp_dir) { |file|
		if file != stylecheck_file && file != bookinfo_file && file != working_file && file != submitter_file && file != tmp_dir
			logger.info('validator_cleanup') {"error log found in tmpdir: #{file}"}
			errlog = true
		end
	}
end

case
when filename_normalized =~ /^.*_IN_PROGRESS.txt/
	logger.info('validator_mailer') {"this is a validator marker file, skipping (e.g. IN_PROGRESS)"}	
when File.file?(errFile)
	logger.info('validator_cleanup') {"errFile found, indicating file failed basic validation, moving orig & errNotice from IN to OUT folder"}
	FileUtils.mv input_file, outbox
	FileUtils.mv errFile, outbox
when !File.file?(bookinfo_file) || (File.file?(stylecheck_file) && !stylecheck_styled)
	FileUtils.mv input_file, outbox	  #return the original file to user
	if !File.file?(bookinfo_file)
    	logger.info('validator_cleanup') {"book_info.json missing, returned orig file and isbn lookup error notice to user, exiting cleanup"}
    	File.open(err_notice, 'w') { |f|
    		f.puts "isbn lookup failed for file #{filename_normalized}, bookmaker_validator could not run! Please double-check the isbn in your filename!"
    	}
    else
		logger.info('validator_cleanup') {"adding warn notice to outbox for unstyled doc"}
		File.open(warn_notice, 'w') { |f|
        	f.puts "WARNING: Your document is NOT STYLED. Bookmaker_validator cannot run on an unstyled document."
    	}
	end
	FileUtils.rm_rf tmp_dir   #alt:  could keep the tmpdir for review like following case	
when errlog || !File.file?(stylecheck_file) || (File.file?(stylecheck_file) && !stylecheck_complete)
	logger.info('validator_cleanup') {"a major error(ALERT) was detected while running macros on \"#{filename_normalized}\", moving tmpdir to logfolder for further study"}
	FileUtils.mv tmp_dir, "#{tmp_dir}__#{timestamp}"  #rename folder
	FileUtils.mv "#{tmp_dir}__#{timestamp}", logfolder 
	FileUtils.mv input_file, outbox
    File.open(err_notice, 'w') { |f|
        f.puts "Bookmaker_validator failed for file #{filename_normalized}. Please email workflows@macmillan.com for help!"
    }
    logger.info('validator_cleanup') {"returned orig file and error notice to user, exitng cleanup"}
else
	logger.info('validator_cleanup') {"file \"#{filename_normalized}\" processing complete, renaming and moving to OUT folder"}
	File.rename(working_file, done_file)
	FileUtils.mv done_file, outbox
	FileUtils.mv input_file, outbox
	FileUtils.rm_rf tmp_dir
	logger.info('validator_cleanup') {"processing of \"#{filename_normalized}\" completed"}
end
if isbn_mismatch
 	logger.info('validator_cleanup') {"adding warn notice to outbox for isbn mismatch"}
 	File.open(warn_notice, 'a') { |f|
       	f.puts "WARNING: ISBN mismatch: the ISBN in your document's filename does not match one found in the manuscript."
   	}
end 

if File.file?(inprogress_file) then FileUtils.rm inprogress_file end