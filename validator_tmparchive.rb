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


# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
#clean up dummy logs from previous run:
Find.find(logfolder) { |file|
	if file =~ /^.*_IN_PROGRESS_log.txt/ then FileUtils.rm_f file end
}
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")  #should we add a timestamp or let them append?)
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end
FileUtils.mkdir_p logfolder  #unnecessary?

logger.info "############################################################################"
logger.info('validator_tmparchive') {"file \"#{filename_normalized}\" was dropped into the #{project_name} folder"}


#--------------------- RUN
if extension =~ /.doc/
	logger.info('validator_tmparchive') {"\"#{basename_normalized}\" is a .doc or .docx, moving to tmpdir"}
    tmp_dir=File.join(working_dir, basename_normalized) 
    working_file = File.join(tmp_dir, filename_normalized)
    inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
    FileUtils.mkdir_p tmp_dir
    File.open(inprogress_file, 'w') { |f|
        f.puts "Processing in progress for file #{filename_normalized}."
    }
    FileUtils.cp input_file, working_file
elsif filename_normalized =~ /^.*_IN_PROGRESS.txt/ || filename_normalized =~ /ERROR_RUNNING_.*.txt/
	logger.info('validator_tmparchive') {"ignoring our own .txt outfile"}
else
    logger.info('validator_tmparchive') {"This is not a .doc or .docx file, posting error.txt to the inbox for user."}
    errFile = File.join(inbox, "ERROR_RUNNING_#{filename_normalized}.txt")
    File.open(errFile, 'w') { |f|
        f.puts "Unable to process \"#{filename_normalized}\", It is not a .doc or .docx."
    }
end


