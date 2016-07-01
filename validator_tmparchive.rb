ENV["NLS_LANG"] = "AMERICAN_AMERICA.WE8MSWIN1252"

require 'fileutils'
require 'logger'
require 'oci8'
require 'to_xml'
require 'json'
require 'dropbox_sdk'
require 'net/smtp'
require 'open3'
require_relative '../utilities/oraclequery.rb'
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
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
tmp_dir=File.join(working_dir, basename_normalized)
validator_dir = File.expand_path(File.dirname(__FILE__))
mailer_dir = File.join(validator_dir,'mailer_messages')
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json')
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json') 
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
errFile = File.join(project_dir, "ERROR_RUNNING_#{filename_normalized}.txt")
thisscript = File.basename($0,'.rb')


# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt") 
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{thisscript} -- #{msg}\n"
end
FileUtils.mkdir_p logfolder


# ---------------------- LOCAL VARIABLES
inprogress_file = File.join(project_dir,"#{filename_normalized}_IN_PROGRESS.txt")
dropbox_filepath = File.join('/', project_name, 'IN', filename_split)
bookmaker_authkeys_file = File.join(validator_dir,'..','bookmaker_authkeys','access_token.txt')
generated_access_token = File.read(bookmaker_authkeys_file)
root_metadata = ''
run_macro = File.join(validator_dir,'run_macro.ps1')
powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
macro_name = "Reports.IsbnSearch"
file_recd_text = File.read(File.join(mailer_dir,'file_received.txt'))
contacts_hash = {} 
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
status_hash['filename_isbn'] = {"isbn"=> ''}
status_hash['filename_isbn']['checkdigit'] = ''
status_hash['isbn_lookup_ok'] = true
status_hash['pisbn_lookup_ok'] = ''
status_hash['pisbns_match'] = true
#status_hash['pisbn_checkdigit_fail'] = []
status_hash['isbnstring'] = ''
status_hash['doc_isbn_list'] = []
status_hash['docisbn_check'] = false
status_hash['docisbn_checkdigit_fail'] = []
status_hash['docisbn_lookup_fail'] = []	
status_hash['docisbn_match_fail'] = []
status_hash['pisbns'] = []




#---------------------  FUNCTIONS
def getbookinfo(lookup_isbn, pisbn_or_isbn_lookup_ok, status_hash, bookinfo_file)
    thissql_F = exactSearchSingleKey(lookup_isbn, "EDITION_EAN")
    myhash_F = runQuery(thissql_F)	

    #verify that data warehouse returned something
    if myhash_F.nil? or myhash_F.empty? or !myhash_F or myhash_F['book'].nil? or myhash_F['book'].empty? or !myhash_F['book'] 
        #logger.info {"data warehouse lookup on isbn_num \"#{lookup_isbn}\"failed, setting status: \'#{pisbn_or_isbn_lookup_ok}\' to false"}
        loginfo = "data warehouse lookup on isbn_num \"#{lookup_isbn}\"failed, setting status: \'#{pisbn_or_isbn_lookup_ok}\' to false"
		status_hash[pisbn_or_isbn_lookup_ok] = false
    else  #lookup was good, continue: 
		thissql_C = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Manager")
		myhash_C = runPeopleQuery(thissql_C)	
		if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book'] 
			pm_name = ''
			loginfo = "no pm found for this EDITION_EAN"			
		else
			pm_name = myhash_C['book']['PERSON_REALNAME'][0]
		end
   		thissql_D = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Editor")
        myhash_D = runPeopleQuery(thissql_D)
        if myhash_D.nil? or myhash_D.empty? or !myhash_D or myhash_D['book'].nil? or myhash_D['book'].empty? or !myhash_D['book'] 
			pe_name = ''
			loginfo = "no pm found for this EDITION_EAN"
		else
			pe_name = myhash_D['book']['PERSON_REALNAME'][0]
		end
		
        #write to var for logs:
        title = myhash_F['book']['WORK_COVERTITLE'][0]
        author = myhash_F['book']['WORK_COVERAUTHOR'][0]
        imprint = myhash_F['book']['IMPRINT_DISPLAY'][0]
        product_type = myhash_F['book']['PRODUCTTYPE_DESC'][0]

        #get alternate isbns:
        thissql_E = exactSearchSingleKey(myhash_F['book']['WORK_ID'][0], "WORK_ID")
        editionshash_B = runQuery(thissql_E)
        isbnarray = []
        editionshash_B.each { |book, hash|
          hash.each { |k,v|
            if k == 'EDITION_EAN' then isbnarray << v end  
          }
        }        
        
        #write to hash
        book_hash = {}
        book_hash.merge!(production_editor: pe_name)
        book_hash.merge!(production_manager: pm_name)
        book_hash.merge!(work_id: myhash_F['book']['WORK_ID'][0])        
        book_hash.merge!(isbn: lookup_isbn)
        book_hash.merge!(title: title)
        book_hash.merge!(author: author)
        book_hash.merge!(product_type: product_type)
        book_hash.merge!(imprint: imprint)   
        book_hash.merge!(alt_isbns: isbnarray)     

        #write json:
        Vldtr::Tools.write_json(book_hash, bookinfo_file)

        status_hash[pisbn_or_isbn_lookup_ok] = true
        #logger.info {"bookinfo from #{isbn} OK- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""}    
		loginfo = "bookinfo from #{lookup_isbn} OK- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""
	end
	loginfo
end


#--------------------- RUN
#kick off logging
logger.info "############################################################################"
logger.info {"file \"#{filename_normalized}\" was dropped into the #{project_name} folder"}

#for testing, to comment out later
#File.open(inprogress_file, 'w') { |f|
#	f.puts "\"#{filename_normalized}\"is being processed"
#}

#clean old, make new tmpdir
#if Dir.exists?(tmp_dir)	then FileUtils.rm_rf tmp_dir end
FileUtils.mkdir_p tmp_dir

#try to get submitter info (Dropbox document 'modifier' via api)
begin
	client = DropboxClient.new(generated_access_token)
	root_metadata = client.metadata(dropbox_filepath)
	user_email = root_metadata["modifier"]["email"]
	user_name = root_metadata["modifier"]["display_name"]
rescue Exception => e  
	p e   #puts e.inspect
end

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
to_address, cc_address, subject, body = '','',''
if status_hash['api_ok'] && user_email =~ /@/ 
	to_address = "To: #{user_name} <#{user_email}>"
    cc_address = "CC: Workflows <workflows@macmillan.com>"
    subject = "File: \"#{filename_split}\" being processed by #{project_name}"
    body = file_recd_text.gsub(/FILENAME_NORMALIZED/,filename_normalized).gsub(/PROJECT_NAME/,project_name)
message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
#{to_address}
#{cc_address}
Subject: #{subject}

#{body}
MESSAGE_END

	unless File.file?(testing_value_file)
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end	
else
	to_address = "To: Workflows <workflows@macmillan.com>"
    subject = "ERROR: dropbox api lookup failure"
    body = "Dropbox api lookup failed for file: #{filename_split}. (found email address: \"#{user_email}\")" 
message_b = <<MESSAGE_B_END
From: Workflows <workflows@macmillan.com>
#{to_address}
Subject: #{subject}

#{body}
MESSAGE_B_END
	
	unless File.file?(testing_value_file)	
		Vldtr::Tools.sendmail(message_b,'workflows@macmillan.com','')
	end
end


#test fileext for =~ .doc
if extension !~ /.doc($|x$)/    
    status_hash['docfile'] = false
    logger.info {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
    File.open(errFile, 'w') { |f|
        f.puts "Unable to process \"#{filename_normalized}\". Your document is not a .doc or .docx file."
    }
else
    #if its a .doc(x) lets go ahead and make a working copy
    FileUtils.cp input_file, working_file  
end


#try lookup on filename isbn
if filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && extension =~ /.doc($|x$)/
    lookup_isbn = filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    status_hash['filename_isbn']["isbn"] = lookup_isbn
    if Vldtr::Tools.checkisbn(lookup_isbn)
        status_hash['filename_isbn']['checkdigit'] = true  
        logger.info {"got isbn \"#{lookup_isbn}\" from filename proceeding with getting book info"}
        lookuplog = getbookinfo(lookup_isbn,'isbn_lookup_ok',status_hash,bookinfo_file)
		logger.info {lookuplog}
    else
        status_hash['filename_isbn']['checkdigit'] = false
		status_hash['isbn_lookup_ok'] = false
        logger.info {"got isbn \"#{lookup_isbn}\" from filename but checkdigit failed, moving on to pisbns"}
    end     
end


#if no or bad isbn exists in filename or filename isbn lookup failed, see if we can find a good pisbn from manuscript!
if (!status_hash['isbn_lookup_ok'] || filename_normalized !~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/) && extension =~ /.doc($|x$)/
    logger.info {"\"#{basename_normalized}\" is a .doc or .docx with bad or missing isbn_num in title, checking manuscript"}
    #get isbns from Manuscript
	status_hash['docisbn_check'] = true
    Open3.popen2e("#{powershell_exe} \"#{run_macro} \'#{input_file}\' \'#{macro_name}\' \'#{logfile}\'\"") do |stdin, stdouterr, wait_thr|
    stdin.close
    stdouterr.each { |line|
      status_hash['isbnstring'] << line
      }
    end
    logger.info {"pulled isbnstring from manuscript & added to status.json: #{status_hash['isbnstring']}"}   
    isbn_array = status_hash['isbnstring'].gsub(/-/,'').split(',')
    isbn_array.each { |i|
        if i =~ /97(8|9)[0-9]{10}/
            if Vldtr::Tools.checkisbn(i)
                status_hash['doc_isbn_list'] << i
            else
                logger.info {"isbn from manuscript failed checkdigit: #{i}"}
                status_hash['docisbn_checkdigit_fail'] << i
            end    
        end
    }
    status_hash['doc_isbn_list'] = status_hash['doc_isbn_list'].uniq
    unique_isbns = status_hash['doc_isbn_list']
    if unique_isbns.empty? || unique_isbns.length > 10
        logger.info {"either 0 (or >10) good isbns found in status_hash['isbnstring'] :( "}
    else
        logger.info {"#{unique_isbns.length} good isbns found in isbnstring; looking them up @ data warehouse"}         
        #now we go get work ids for each isbn... 
        unique_isbns.each { |j|
            thissql = exactSearchSingleKey(j, "EDITION_EAN")
            myhash = runQuery(thissql)
            if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book'] 
                logger.info {"isbn data-warehouse-lookup for manuscript isbn: #{j} failed."}
				status_hash['docisbn_lookup_fail'] << j
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
        if status_hash['pisbns'].length > 1
            logger.info {"too many pisbns found via doc_isbn lookup: marking pisbn_match false."}
            status_hash['pisbns_match'] = false
        elsif status_hash['pisbns'].length == 1
            #perform book info lookup on good pisbn!
            logger.info {"found a good pisbn #{status_hash['pisbns'][0]} from doc_isbn workid(s), using that for lookups!"}
            lookuplog = getbookinfo(status_hash['pisbns'][0],'pisbn_lookup_ok',status_hash,bookinfo_file)   
			logger.info {lookuplog}
        end            
    end       
end

Vldtr::Tools.write_json(status_hash, status_file)
if !File.file?(bookinfo_file)
	logger.info {"no bookinfo file present, will be skipping Validator macro"}
end