require 'fileutils'
require 'logger'
require 'find'

# ---------------------- VARIABLES
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = filename_split.gsub(/ /, "")
basename_normalized = File.basename(filename_normalized, ".*")
extension = File.extname(filename_normalized)
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
tmp_dir=File.join(working_dir, basename_normalized) 
working_file = File.join(tmp_dir, filename_normalized)
done_file = File.join(tmp_dir, "#{basename_normalized}_DONE#{extension}")
inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
errlog = false
errfile = ''
err_notice = File.join(outbox,"ERROR--#{filename_normalized}--Validator_Failed.txt")


# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt") 
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end


#--------------------- RUN
#check for errlog in tmp_dir:
Find.find(tmp_dir) { |file|
	if file =~ /^.*\.(txt|json|log)/ && file !~ /^.*userinfo.json/
		logger.info('validator_mailer') {"error log found in tmpdir: #{file}, setting email text accordingly"}
		errlog = true
		errfile = file
	end
}

if errlog
	logger.info('validator_cleanup') {"a major error was detected while running macros on \"#{filename_normalized}\""}
	FileUtils.cp(errfile, logfolder)   #copy error logfile to logdir
	FileUtils.rm_rf tmp_dir     #optionally still delete tmp_dir for file:
	#TODO here:  invoke mailer / alert for us. or have that as separate script.
	# or maybe that's a separate .rb script that runs prior to this one if errfile exists
	FileUtils.mv input_file, outbox	  #returm the original file
    File.open(err_notice, 'w') { |f|
        f.puts "Bookmaker_validator failed for file #{filename_normalized}. Please email workflows@macmillan.com for help!"
    }
else
	if Dir.exist?(tmp_dir)
		logger.info('validator_cleanup') {"file \"#{filename_normalized}\" processing complete, renaming and moving to OUT folder"}
		File.rename(working_file, done_file)
		FileUtils.cp_r "#{tmp_dir}/.", outbox
		FileUtils.mv input_file, outbox
		FileUtils.rm_rf tmp_dir
		logger.info('validator_cleanup') {"processing of \"#{filename_normalized}\" completed"}
	end
end
FileUtils.rm inprogress_file
