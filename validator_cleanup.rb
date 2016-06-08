require 'fileutils'
require 'logger'
require 'find'

# ---------------------- VARIABLES (HEADER)
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = filename_split.scan( /[^[:alnum:]\._-]/ ) { |badchar| filename_split=filename_split.tr(badchar,'') } #strip any chars but alphanumeric, plus these 3 .-_
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
submitter_file = File.join(tmp_dir,'submitter.json')
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
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
errlog = false
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
backup_tmp_dir = File.join(logfolder, "#{tmp_dir}_#{timestamp}")


#--------------------- RUN
#check for errlog in tmp_dir:
Find.find(tmp_dir) { |file|
	if file != stylecheck_file && file != bookinfo_file && file != working_file && file != submitter_file
		logger.info('validator_cleanup') {"error log found in tmpdir: #{file}"}
		errlog = true
	end
}

if errlog
	logger.info('validator_cleanup') {"a major error(ALERT) was detected while running macros on \"#{filename_normalized}\", moving tmpdir to logfolder for further study"}
	FileUtils.mv tmp_dir, backup_tmp_dir  
	FileUtils.mv input_file, outbox	  #returm the original file to user
    File.open(err_notice, 'w') { |f|
        f.puts "Bookmaker_validator failed for file #{filename_normalized}. Please email workflows@macmillan.com for help!"
    }
    logger.info('validator_cleanup') {"returned orig file and error notice to user, exitng cleanup"}
elsif Dir.exist?(tmp_dir)
	if !File.file?(bookinfo_file)
		FileUtils.mv input_file, outbox	  #returm the original file to user
    	File.open(err_notice, 'w') { |f|
	        f.puts "isbn lookup failed for file #{filename_normalized}, bookmaker_validator could not run! Please double-check the isbn in your filename!"
	    }
	    logger.info('validator_cleanup') {"book_info.json missing, returned orig file and isbn lookup error notice to user, exitng cleanup"}
	end	
	logger.info('validator_cleanup') {"file \"#{filename_normalized}\" processing complete, renaming and moving to OUT folder"}
	File.rename(working_file, done_file)
	FileUtils.cp_r "#{tmp_dir}/.", outbox
	FileUtils.mv input_file, outbox
	FileUtils.rm_rf tmp_dir
	logger.info('validator_cleanup') {"processing of \"#{filename_normalized}\" completed"}
elsif File.file?(errFile)
	logger.info('validator_cleanup') {"errFile found, indicating file failed basic validation, moving orig & errNotice from IN to OUT folder"}
	FileUtils.mv input_file, outbox
	FileUtils.mv errFile, outbox
end
if File.file?(inprogress_file) then FileUtils.rm inprogress_file end