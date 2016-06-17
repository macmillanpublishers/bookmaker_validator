ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

require 'fileutils'
require 'logger'
require 'find'
require 'oci8'
require 'to_xml'
require 'json'
require 'dropbox_sdk'
require 'net/smtp'
require 'open3'
require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
#Mcmlln::Tools.cmd
#Vldtr::Tools.cmd

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
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json') 
testing_value_file = File.join("C:", "staging.txt")
#inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
errFile = File.join(project_dir, "ERROR_RUNNING_#{filename_normalized}.txt")


# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt") 
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end
FileUtils.mkdir_p logfolder


# ---------------------- LOCAL VARIABLES
dropbox_filepath = File.join('/', project_name, 'IN', filename_split)
bookmaker_authkeys_dir = File.join(File.dirname(__FILE__), '../bookmaker_authkeys')
generated_access_token = File.read("#{bookmaker_authkeys_dir}/access_token.txt")
run_macro = File.join('S:','resources','bookmaker_scripts','bookmaker_validator','run_macro.ps1')
powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
macro_name="Reports.IsbnSearch"
contacts_datahash = {} 
status_datahash = {}
status_datahash['api_ok'] = true
status_datahash['docfile'] = true
status_datahash['filename_isbn'] = true
status_datahash['isbnstring'] = ''
status_datahash['isbns_match'] = true
status_datahash['doc_isbn_list'] = []
status_datahash['pisbns'] = []


#--------------------- RUN
# #clean up dummy logs from previous run:
# Find.find(logfolder) { |file|
#     if file =~ /^.*_IN_PROGRESS_log.txt/ then FileUtils.rm_f file end
# }
#kick off logging
logger.info "############################################################################"
logger.info('validator_tmparchive') {"file \"#{filename_normalized}\" was dropped into the #{project_name} folder"}

#make tmpdir
FileUtils.mkdir_p tmp_dir

#get submitter info (Dropbox document 'modifier' via api)
client = DropboxClient.new(generated_access_token)
root_metadata = client.metadata(dropbox_filepath)
user_email = root_metadata["modifier"]["email"]
user_name = root_metadata["modifier"]["display_name"]


if root_metadata.nil? or root_metadata.empty? or !root_metadata or root_metadata['modifier'].nil? or root_metadata['modifier'].empty? or !root_metadata['modifier'] 
    status_datahash['api_ok'] = false
    logger.info('validator_mailer') {"dropbox api may have failed, not finding file metadata"}
else
    #writing user info from Dropbox API to json
    contacts_datahash.merge!(submitter_name: user_name)
    contacts_datahash.merge!(submitter_email: user_email)
    contactsjson = JSON.generate(contacts_datahash)
    Vldtr::Tools.write_json(contactsjson,contacts_file)
    logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", wrote to contacts.json"}    
end


if extension !~ /.doc/      #test fileext for =~ .doc
    status_datahash['docfile'] = false
    logger.info('validator_tmparchive') {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
    File.open(errFile, 'w') { |f|
        f.puts "Unable to process \"#{filename_normalized}\". Your document is not a .doc or .docx file."
    }
else
    #if its a .doc(x) lets go ahead and make a working copy
    FileUtils.cp input_file, working_file          
end


#if no isbn exists in filename, see if we can find a good pisbn from manuscript!
if filename_normalized !~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && extension =~ /.doc/ 
    logger.info('validator_tmparchive') {"\"#{basename_normalized}\" is a .doc or .docx with no isbn_num in title, checking manuscript"}
    
    #get isbns from Manuscript
    status_datahash['filename_isbn'] = false
    Open3.popen2e("#{powershell_exe} \"#{run_macro} \'#{input_file}\' \'#{macro_name}\' \'#{logfile}\'\"") do |stdin, stdouterr, wait_thr|
    stdin.close
    stdouterr.each { |line|
      status_datahash['isbnstring'] << line
      }
    end
    logger.info('validator_tmparchive') {"isbnstring pulled from manuscript & added to status.json}"}   
    isbn_array = status_datahash['isbnstring'].gsub!(/[^0-9,]/,'').split(',')
    isbn_array.each { |i|
        if i ~= /97(8|9)[0-9]{10}/
           status_datahash['doc_isbn_list'] << i
        end
    }
    unique_isbns = status_datahash['doc_isbn_list'].uniq
    if unique_isbns.empty? || unique_isbns.length > 20
        logger.info('validator_tmparchive') {"either 0 (or >20) good isbns found in status_datahash['isbnstring'] :( "}
    else
        logger.info('validator_tmparchive') {"#{unique_isbns.length} good isbns found in isbnstring; looking them up @ data warehouse"}         
        #now we go get work ids for each isbn... 
        unique_isbns.each { |j|
            thissql = exactSearchSingleKey(j, "EDITION_EAN")
            myhash = runPeopleQuery(thissql)
            if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book'] 
                logger.info('validator_tmparchive') {"isbn data-warehouse-lookup for manuscript isbn: #{j} failed."}
            else
                #and now we go get print isbn for each unique workid... 
                thissql_B = exactSearchSingleKey(myhash['book']['WORK_ID'][0], "WORK_ID")
                editionshash = runQuery(thissql_B)
                unless editionshash.nil? or editionshash.empty? or !editionshash
                    editionshash.each do |k, v|
                        # find a print product if it exists
                        if v['PRODUCTTYPE_DESC'] and v['PRODUCTTYPE_DESC'] == "Book"
                            status_datahash['pisbns'] << v['EDITION_EAN']
                        end
                    end
                end
            end    
        } 
        status_datahash['doc_isbn_list'] = status_datahash['doc_isbn_list'].uniq
        if status_datahash['pisbns'].length > 1
            logger.info('validator_tmparchive') {"too many pisbns found via doc_isbn lookup: marking isbn_match false."}
            status_datahash['isbns_match'] = false
        elsif status_datahash['pisbns'].length = 1
            logger.info('validator_tmparchive') {"found a good pisbn #{status_datahash['pisbns'][0]} from doc_isbn workid(s), using that for lookups."} 
        end            
    end       
end

Vldtr::Tools.write_json(status_datahash, status_file)


#perform bookinfo lookup if we have a good isbn
if (filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ || status_datahash['pisbns'].length = 1) && extension =~ /.doc/   
    #check isbn_num against data-warehouse    
    lookup_isbn=''
    if filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
        lookup_isbn = filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
        logger.info('validator_tmparchive') {"got isbn \"#{lookup_isbn}\" from filename proceeding with getting book info"}
    else
        lookup_isbn = status_datahash['pisbns'][0]
    end    

    thissql_C = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Manager")
    myhash_C = runPeopleQuery(thissql_C)
    #verify that data warehouse returned something
    if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book'] 
        logger.info('validator_tmparchive') {"data warehouse lookup on isbn_num \"#{lookup_isbn}\"failed, skipping write to json"}
    else  #lookup was good, continue: 
        logger.info('validator_tmparchive') {"data warehouse lookup PM for isbn_num \"#{lookup_isbn}\"succeeded, looking up PE, writing to json, exiting tmparchive.rb"}
        thissql_D = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Editor")
        myhash_D = runPeopleQuery(thissql_D)
		
		#write to var for logs:
		title = myhash_C['book']['WORK_COVERTITLE'][0]
		author = myhash_C['book']['WORK_COVERAUTHOR'][0]
		imprint = myhash_C['book']['IMPRINT_DISPLAY'][0]
		product_type = myhash_C['book']['PRODUCTTYPE_DESC'][0]
		
		#write to hash for json:
        datahash = {}
        datahash.merge!(production_editor: myhash_D['book']['PERSON_REALNAME'][0])
        datahash.merge!(production_manager: myhash_C['book']['PERSON_REALNAME'][0])
        datahash.merge!(work_id: myhash_C['book']['WORK_ID'][0])		
		datahash.merge!(isbn: lookup_isbn)
        datahash.merge!(title: title)
        datahash.merge!(author: author)
        datahash.merge!(product_type: product_type)
        datahash.merge!(imprint: imprint)	

        # Printing final JSON object
        Vldtr::Tools.write_json(datahash, bookinfo_file)

		logger.info('validator_tmparchive') {"bookinfo- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""}		
    end    
end


