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
validator_dir = File.dirname(__FILE__)
mailer_dir = File.join(validator_dir,'mailer_messages')
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
#bookmaker_authkeys_dir = File.join(File.dirname(__FILE__), '../bookmaker_authkeys')
#generated_access_token = File.read("#{bookmaker_authkeys_dir}/access_token.txt")
bookmaker_authkeys_file = File.join(validator_dir,'..','bookmaker_authkeys','access_token.txt')
generated_access_token = File.read(bookmaker_authkeys_file)
#run_macro = File.join('S:','resources','bookmaker_scripts','bookmaker_validator','run_macro.ps1')
run_macro = File.join(validator_dir,'run_macro.ps1')
powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
macro_name = "Reports.IsbnSearch"
file_recd_text = File.read(File.join(mailer_dir,'file_received.txt'))
contacts_hash = {} 
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
status_hash['filename_isbn'] = {"isbn"=> ''}
status_hash['filename_isbn'] = {"checkdigit"=> false}
status_hash['isbn_lookup_ok'] = true
status_hash['pisbn_lookup_ok'] = true
status_hash['pisbns_match'] = true
status_hash['pisbn_checkdigit_fail'] = []
status_hash['isbnstring'] = ''
status_hash['doc_isbn_list'] = []
status_hash['pisbns'] = []



#---------------------  FUNCTIONS
def getbookinfo(lookup_isbn,pisbn_or_isbn_lookup_ok)
    thissql_C = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Manager")
    myhash_C = runPeopleQuery(thissql_C)

    #verify that data warehouse returned something
    if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book'] 
        logger.info('validator_tmparchive') {"data warehouse lookup on isbn_num \"#{lookup_isbn}\"failed, setting status: \'#{pisbn_or_isbn_lookup_ok}\' to false"}
        status_hash['pisbn_or_isbn_lookup_ok'] = false
    else  #lookup was good, continue: 
        logger.info('validator_tmparchive') {"data warehouse lookup PM for isbn_num \"#{lookup_isbn}\"succeeded, looking up PE, writing to json, exiting tmparchive.rb"}
        thissql_D = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Editor")
        myhash_D = runPeopleQuery(thissql_D)
        
        #write to var for logs:
        title = myhash_C['book']['WORK_COVERTITLE'][0]
        author = myhash_C['book']['WORK_COVERAUTHOR'][0]
        imprint = myhash_C['book']['IMPRINT_DISPLAY'][0]
        product_type = myhash_C['book']['PRODUCTTYPE_DESC'][0]
        
        #write to hash, write json:
        book_hash = {}
        book_hash.merge!(production_editor: myhash_D['book']['PERSON_REALNAME'][0])
        book_hash.merge!(production_manager: myhash_C['book']['PERSON_REALNAME'][0])
        book_hash.merge!(work_id: myhash_C['book']['WORK_ID'][0])        
        book_hash.merge!(isbn: lookup_isbn)
        book_hash.merge!(title: title)
        book_hash.merge!(author: author)
        book_hash.merge!(product_type: product_type)
        book_hash.merge!(imprint: imprint)   

        Vldtr::Tools.write_json(book_hash, bookinfo_file)

        status_hash['pisbn_or_isbn_lookup_ok'] = true
        logger.info('validator_tmparchive') {"bookinfo from #{pisbn_or_isbn} #{isbn}- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""}    
end



#--------------------- RUN
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
    status_hash['api_ok'] = false
    contacts_hash.merge!(submitter_name: 'Workflows')
    contacts_hash.merge!(submitter_email: 'workflows@macmillan.com')
    logger.info('validator_mailer') {"dropbox api may have failed, not finding file metadata"}
else
    #writing user info from Dropbox API to json
    contacts_hash.merge!(submitter_name: user_name)
    contacts_hash.merge!(submitter_email: user_email)
    Vldtr::Tools.write_json(contacts_hash,contacts_file)
    logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", wrote to contacts.json"}    
end

#send email upon file receipt:
cc_address, subject, body = '','',''
message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
#{cc_address}
Subject: #{subject}

#{body}
MESSAGE_END

if status_hash['api_ok'] && user_email =~ /@/ 
    cc_address = "CC: Workflows <workflows@macmillan.com>"
    subject = "File: \"filename_normalized\" being processed by #{project_name}"
    body = file_recd_text.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name)
    Vldtr::Tools.sendmail(message_a,user_email,'workflows@macmillan.com')
else    
    subject = "ERROR: dropbox api lookup failure"
    body = "Dropbox api lookup failed for file: #{input_file}, (found email is: \"#{user_email}\")"    
    Vldtr::Tools.sendmail(message_b,'workflows@macmillan.com','')
end


#test fileext for =~ .doc
if extension !~ /.doc/      
    status_hash['docfile'] = false
    logger.info('validator_tmparchive') {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
    File.open(errFile, 'w') { |f|
        f.puts "Unable to process \"#{filename_normalized}\". Your document is not a .doc or .docx file."
    }
else
    #if its a .doc(x) lets go ahead and make a working copy
    FileUtils.cp input_file, working_file          
end


#try lookup on filename isbn
if (filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    lookup_isbn = filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    status_hash['filename_isbn']["isbn"] = lookup_isbn
    if Vldtr::Tools.checkisbn(lookup_isbn)
        status_hash['filename_isbn']['checkdigit'] = true  
        logger.info('validator_tmparchive') {"got isbn \"#{lookup_isbn}\" from filename proceeding with getting book info"}
        getbookinfo(lookup_isbn,'isbn_lookup_ok')
    else
        status_hash['isbn_lookup_ok'] = false
        logger.info('validator_tmparchive') {"got isbn \"#{lookup_isbn}\" from filename but checkdigit failed, moving on to pisbns"}
    end     
end


#if no or bad isbn exists in filename or filename isbn lookup failed, see if we can find a good pisbn from manuscript!
if (status_hash['isbn_lookup_ok'] = false || filename_normalized !~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/) && extension =~ /.doc/ 
    logger.info('validator_tmparchive') {"\"#{basename_normalized}\" is a .doc or .docx with no isbn_num in title, checking manuscript"}
    
    #get isbns from Manuscript
    Open3.popen2e("#{powershell_exe} \"#{run_macro} \'#{input_file}\' \'#{macro_name}\' \'#{logfile}\'\"") do |stdin, stdouterr, wait_thr|
    stdin.close
    stdouterr.each { |line|
      status_hash['isbnstring'] << line
      }
    end
    logger.info('validator_tmparchive') {"isbnstring pulled from manuscript & added to status.json"}   
    isbn_array = status_hash['isbnstring'].gsub!(/[^0-9,]/,'').split(',')
    isbn_array.each { |i|
        if i =~ /97(8|9)[0-9]{10}/
            if Vldtr::Tools.checkisbn(i)
                status_hash['doc_isbn_list'] << i
            else
                logger.info('validator_tmparchive') {"isbn from manuscript failed checkdigit: #{i}"}
                status_hash['pisbn_checkdigit_fail'] << i
            end    
        end
    }
    unique_isbns = status_hash['doc_isbn_list'].uniq
    if unique_isbns.empty? || unique_isbns.length > 10
        logger.info('validator_tmparchive') {"either 0 (or >10) good isbns found in status_hash['isbnstring'] :( "}
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
                            status_hash['pisbns'] << v['EDITION_EAN']
                        end
                    end
                end
            end    
        } 
        status_hash['doc_isbn_list'] = status_hash['doc_isbn_list'].uniq
        if status_hash['pisbns'].length > 1
            logger.info('validator_tmparchive') {"too many pisbns found via doc_isbn lookup: marking pisbn_match false."}
            status_hash['pisbns_match'] = false
        elsif status_hash['pisbns'].length = 1
            #perform book info lookup on good pisbn!
            logger.info('validator_tmparchive') {"found a good pisbn #{status_hash['pisbns'][0]} from doc_isbn workid(s), using that for lookups!"}
            getbookinfo(status_hash['pisbns'][0],'pisbn_lookup_ok')   
        end            
    end       
end

Vldtr::Tools.write_json(status_hash, status_file)


