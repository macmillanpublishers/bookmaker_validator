ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

## FOR TESTING  undo these for production, and untoggle lines:  12/13, 27/28, 30/31

require 'fileutils'
require 'logger'
require 'find'
require 'oci8'
require 'to_xml'
require 'json'
#require_relative '../utilities/oraclequery.rb'
require_relative '../../../bookmaker-dev/utilities/oraclequery.rb'

# ---------------------- VARIABLES (HEADER)
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = string.scan( /[^[:alnum:]\._-]/ ) { |badchar| string=string.tr(badchar,'') } #strip any chars but alphanumeric, plus these 3 .-_
basename_normalized = File.basename(filename_normalized, ".*")
extension = File.extname(filename_normalized)
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
#working_dir = 
tmp_dir=File.join(working_dir, basename_normalized)
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "nothing.txt")  #for testing
json_file = File.join(tmp_dir,'info.json')

# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt") 
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end
FileUtils.mkdir_p logfolder


# ---------------------- LOCAL VARIABLES
isbn_namecheck = false
isbn_lookupcheck = false

#--------------------- RUN
#clean up dummy logs from previous run:
Find.find(logfolder) { |file|
    if file =~ /^.*_IN_PROGRESS_log.txt/ then FileUtils.rm_f file end
}
#kick off logging
logger.info "############################################################################"
logger.info('validator_tmparchive') {"file \"#{filename_normalized}\" was dropped into the #{project_name} folder"}

# check for isbn in filename:
if filename_normalized =~ /9(78|-78|7-8|78-|-7-8)[0-9,-]{10,14}/
    isbn_check = true
    isbn = filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9,-]{10,14}/).to_s.tr('-','').slice(0..12)
end

#lookup info on isbn at data warehouse
thissql = personSearchSingleKey(isbn, "EDITION_EAN", "Production Manager")
myhash = runPeopleQuery(thissql)

unless myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book']
    isbn_lookupcheck = true
    thissql_B = personSearchSingleKey(isbn, "EDITION_EAN", "Production Editor")
    myhash_B = runPeopleQuery(thissql_B)
    #puts "DB Connection SUCCESS: Found a PM record"

    #WRITING TO JSON
    datahash = {}
    datahash.merge!(production_editor: myhash_B['book']['PERSON_REALNAME'][0])
    datahash.merge!(production_manager: myhash['book']['PERSON_REALNAME'][0])
    datahash.merge!(title: myhash['book']['WORK_COVERTITLE'][0])
    datahash.merge!(author: myhash['book']['WORK_COVERAUTHOR'][0])
    datahash.merge!(product_type: myhash['book']['PRODUCTTYPE_DESC'][0])
    datahash.merge!(imprint: myhash['book']['IMPRINT_DISPLAY'][0])
    finaljson = JSON.generate(datahash)

    # Printing the final JSON object
    File.open(json_file, 'w+:UTF-8') do |f|
      f.puts finaljson
    end
else
    puts "No DB record found; removing author links for addons"
end



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


