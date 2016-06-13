ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

require 'fileutils'
require 'logger'
require 'find'
require 'oci8'
require 'to_xml'
require 'json'
require_relative '../utilities/oraclequery.rb'

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
FileUtils.mkdir_p logfolder


#--------------------- RUN
#clean up dummy logs from previous run:
Find.find(logfolder) { |file|
    if file =~ /^.*_IN_PROGRESS_log.txt/ then FileUtils.rm_f file end
}
#kick off logging
logger.info "############################################################################"
logger.info('validator_tmparchive') {"file \"#{filename_normalized}\" was dropped into the #{project_name} folder"}

#test filename for isbn_num and fyle type for =~ .doc
if extension =~ /.doc/ && filename_normalized =~ /9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/

    #move file into tmparchive
    logger.info('validator_tmparchive') {"\"#{basename_normalized}\" is a .doc or .docx with isbn_num in title, moving to tmpdir"}
    FileUtils.mkdir_p tmp_dir
    File.open(inprogress_file, 'w') { |f|
        f.puts "Processing in progress for file #{filename_normalized}."
    }
    FileUtils.cp input_file, working_file

    #check isbn_num against data-warehouse
    isbn_num = filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    thissql = personSearchSingleKey(isbn_num, "EDITION_EAN", "Production Manager")
    myhash = runPeopleQuery(thissql)

    #verify that data warehouse returned something
    if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book'] 
        logger.info('validator_tmparchive') {"data warehouse lookup on isbn_num \"#{isbn_num}\"failed, skipping write to json"}

    else  #lookup was good, continue: 
        logger.info('validator_tmparchive') {"data warehouse lookup PM for isbn_num \"#{isbn_num}\"succeeded, looking up PE, writing to json, exiting tmparchive.rb"}
        thissql_B = personSearchSingleKey(isbn_num, "EDITION_EAN", "Production Editor")
        myhash_B = runPeopleQuery(thissql_B)
		
		#write to var for logs:
		title = myhash['book']['WORK_COVERTITLE'][0]
		author = myhash['book']['WORK_COVERAUTHOR'][0]
		imprint = myhash['book']['IMPRINT_DISPLAY'][0]
		product_type = myhash['book']['PRODUCTTYPE_DESC'][0]
		
		#write to hash for json:
        datahash = {}
        datahash.merge!(production_editor: myhash_B['book']['PERSON_REALNAME'][0])
        datahash.merge!(production_manager: myhash['book']['PERSON_REALNAME'][0])
        datahash.merge!(work_id: myhash['book']['WORK_ID'][0])		
		datahash.merge!(isbn: "#{isbn_num}")
        datahash.merge!(title: myhash['book']['WORK_COVERTITLE'][0])
        datahash.merge!(author: myhash['book']['WORK_COVERAUTHOR'][0])
        datahash.merge!(product_type: myhash['book']['PRODUCTTYPE_DESC'][0])
        datahash.merge!(imprint: myhash['book']['IMPRINT_DISPLAY'][0])
        datahash.merge!(isbn_mismatch: false)		
        finaljson = JSON.generate(datahash)

        # Printing final JSON object
        File.open(bookinfo_file, 'w+:UTF-8') do |f|
          f.puts finaljson		
        end
		logger.info('validator_tmparchive') {"bookinfo- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""}		
    end    
elsif filename_normalized =~ /^.*_IN_PROGRESS.txt/ || filename_normalized =~ /ERROR_RUNNING_.*.txt/
	logger.info('validator_tmparchive') {"ignoring our own .txt outfile"}
else
    logger.info('validator_tmparchive') {"This is not a .doc or .docx file or filename contains no ISBN, posting error.txt to the inbox for user; exiting tmparchive.rb."}
    File.open(errFile, 'w') { |f|
        f.puts "Unable to process \"#{filename_normalized}\". Either it is not a .doc or .docx file, or no isbn_num was included in the filename; exiting tmparchive.rb."
    }
end


