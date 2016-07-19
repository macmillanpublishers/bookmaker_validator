require 'fileutils'
require 'dropbox_sdk'
require 'open3'

require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

dropbox_filepath = File.join('/', Val::Paths.project_name, 'IN', Val::Doc.filename_split)
generated_access_token = File.read(File.join(Val::Resources.authkeys_repo,'access_token.txt'))
macro_name = "Validator.IsbnSearch"
file_recd_txt = File.read(File.join(Val::Paths.mailer_dir,'file_received.txt'))
logfile_for_macro = File.join(Val::Logs.logfolder, Val::Logs.logfilename)

root_metadata = ''
contacts_hash = {}
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
status_hash['filename_isbn'] = {"isbn"=> ''}
status_hash['filename_isbn']['checkdigit'] = ''
#status_hash['isbn_lookup_ok'] = true   # renamed
status_hash['filename_isbn_lookup_ok'] = true
status_hash['doc_isbn_lookup_ok'] = ''   #renamed from ['pisbn_lookup_ok']
status_hash['docisbn_string'] = ''    #renamed from isbnstring
status_hash['docisbns'] = []   #new!  every isbn from file that looks right (no checks)
#status_hash['doc_isbn_list'] = []      #deleted
#status_hash['docisbn_check'] = false     # deleted
status_hash['docisbn_checkdigit_fail'] = []
status_hash['docisbn_lookup_fail'] = []
status_hash['docisbn_match_fail'] = []
status_hash['isbn_match_ok'] = true     #renamed from ['pisbns_match']
#status_hash['pisbns'] = []    #deleted
alt_isbn_array = []

docisbns
docisbn_match
docisbn_


#---------------------  FUNCTIONS
#this function quick verifies an isbn: checkdigit, ean lookup.
def testisbn(isbn, whichisbn)
    lookup, loginfo = false, ''
    if Vldtr::Tools.checkisbn(isbn)
        if whichisbn == filename_isbn then status_hash['filename_isbn']['checkdigit'] = true end
        thissql_A = exactSearchSingleKey(isbn, "EDITION_EAN")
        myhash_A = runQuery(thissql_A)
        if myhash_A.nil? or myhash_A.empty? or !myhash_A or myhash_A['book'].nil? or myhash_A['book'].empty? or !myhash_A['book']
            loginfo = "data warehouse lookup on #{whichisbn} \"#{isbn}\" failed, setting status to false"
            if whichisbn == filename_isbn then status_hash['filename_isbn_lookup_ok'] = false end
            if whichisbn == docisbn then status_hash['docisbn_lookup_fail'] << isbn end
        else  #isbn checks out
            lookup = true
        end
    else  #checkdigit failed
        if whichisbn == filename_isbn
            status_hash['filename_isbn']['checkdigit'] = false
            status_hash['filename_isbn_lookup_ok'] = false
        end
        if whichisbn == docisbn then status_hash['docisbn_checkdigit_fail'] << isbn end
        loginfo = "checkdigit failed for #{whichisbn} \"#{isbn}\""
    end
    return loginfo, lookup
end

#this function takes our good isbn, gathers info and writes it to file.
def getbookinfo(lookup_isbn, hash_lookup_string, status_hash, bookinfo_file)
    #do basic lookup b/c we no it will be successful
    loginfo = ''
    thissql_F = exactSearchSingleKey(lookup_isbn, "EDITION_EAN")
    myhash_F = runQuery(thissql_F)
    #now do lookups for PM & PE
		thissql_C = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Manager")
		myhash_C = runPeopleQuery(thissql_C)
		if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book']
  			pm_name = ''
  			loginfo = "no pm found for this EDITION_EAN\n"
		else
  			pm_name = myhash_C['book']['PERSON_REALNAME'][0]
		end
 		thissql_D = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Editor")
    myhash_D = runPeopleQuery(thissql_D)
    if myhash_D.nil? or myhash_D.empty? or !myhash_D or myhash_D['book'].nil? or myhash_D['book'].empty? or !myhash_D['book']
  			pe_name = ''
  			loginfo = "#{loginfo}no pm found for this EDITION_EAN\n"
		else
  			pe_name = myhash_D['book']['PERSON_REALNAME'][0]
		end
        #write to var for logs:
        title = myhash_F['book']['WORK_COVERTITLE']
        author = myhash_F['book']['WORK_COVERAUTHOR']
        imprint = myhash_F['book']['IMPRINT_DISPLAY']
        product_type = myhash_F['book']['PRODUCTTYPE_DESC']
        work_id = myhash_F['book']['WORK_ID']

        #get alternate isbns:
        thissql_E = exactSearchSingleKey(work_id, "WORK_ID")
        editionshash_B = runQuery(thissql_E)
        editionshash_B.each { |book, hash|
          hash.each { |k,v|
            if k == 'EDITION_EAN' then alt_isbn_array << v end
          }
        }

        #write to hash
        book_hash = {}
        book_hash.merge!(production_editor: pe_name)
        book_hash.merge!(production_manager: pm_name)
        book_hash.merge!(work_id: work_id)
        book_hash.merge!(isbn: lookup_isbn)
        book_hash.merge!(title: title)
        book_hash.merge!(author: author)
        book_hash.merge!(product_type: product_type)
        book_hash.merge!(imprint: imprint)
        book_hash.merge!(alt_isbns: alt_isbn_array)

        #write json:
        Vldtr::Tools.write_json(book_hash, bookinfo_file)

        status_hash[hash_lookup_string] = true
		loginfo = "#{loginfo}bookinfo from #{lookup_isbn} OK- title: \"#{title}\", author: \"#{author}\", imprint: \"#{imprint}\", product_type: \"#{product_type}\""
	end
	loginfo
end


#--------------------- RUN
logger.info "############################################################################"
logger.info {"file \"#{Val::Doc.filename_normalized}\" was dropped into the #{Val::Paths.project_name} folder"}

FileUtils.mkdir_p Val::Paths.tmp_dir  #make the tmpdir

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
    Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
    logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", wrote to contacts.json"}
end


#send email upon file receipt, different mails depending on whether drpobox api succeeded:
if status_hash['api_ok'] && user_email =~ /@/
    body = Val::Resources.mailtext_gsubs(file_recd_txt,'','','')

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
CC: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END

	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
else

message_b = <<MESSAGE_B_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ERROR: dropbox api lookup failure

Dropbox api lookup failed for file: #{Val::Doc.filename_split}. (found email address: \"#{user_email}\")
MESSAGE_B_END

	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message_b,'workflows@macmillan.com','')
	end
end


#test fileext for =~ .doc
if Val::Doc.extension !~ /.doc($|x$)/
    status_hash['docfile'] = false
    logger.info {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
    File.open(Val::Files.errFile, 'w') { |f|
        f.puts "Unable to process \"#{Val::Doc.filename_normalized}\". Your document is not a .doc or .docx file."
    }
else
    #if its a .doc(x) lets go ahead and make a working copy
    Mcmlln::Tools.copyFile(Val::Doc.input_file, Val::Files.working_file)
end


#try lookup on filename isbn
if Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && Val::Doc.extension =~ /.doc($|x$)/
    filename_isbn = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    status_hash['filename_isbn']["isbn"] = filename_isbn
    testlog, testlookup = testisbn(filename_isbn, "filename_isbn")
    logger.info {testlog}
    if testlookup == true
        logger.info {"isbn \"#{filename_isbn}\" checked out, proceeding with getting book info"}
        lookuplog = getbookinfo(filename_isbn,'filename_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file)
		    logger.info {lookuplog}
    end
end


#get isbns from Manuscript via macro
# status_hash['docisbn_check'] = true
Open3.popen2e("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro} \'#{Val::Doc.input_file}\' \'#{macro_name}\' \'#{logfile_for_macro}\'\"") do |stdin, stdouterr, wait_thr|
    stdin.close
    stdouterr.each { |line|
        status_hash['docisbn_string'] << line
    }
end
logger.info {"pulled isbnstring from manuscript & added to status.json: #{status_hash['docisbn_string']}"}

#parse isbnstring, verify checkdigit, create aray of good isbns
docisbn_array = status_hash['docisbn_string'].gsub(/-/,'').split(',')
if docisbn_array.length < 10 && !docisbn_array.empty?
    docisbn_array.each { |i|
        if i =~ /97(8|9)[0-9]{10}/
            if alt_isbn_array.include?(i)   #if it matches a filename isbn already
                status_hash['docisbns'] << i
            else
                testlog_b, testlookup_b = testisbn(i, "docisbn")      #quick check the isbn
                logger.info {testlog_b}
                if testlookup_b == true
                    if alt_isbn_array.empty?            #if no isbn array exists yet, this one will be thr primary lookup for bookinfo
                        logger.info {"docisbn \"#{i}\" checked out, no existing primary lookup isbn, proceeding with getting book info"}
                        lookuplog_b = getbookinfo(filename_isbn,'doc_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file)
                		    logger.info {lookuplog}
                        status_hash['docisbns'] << i
                    else            #since an isbn array exists that we don't match, we have a mismatch;
                        logger.info {"lookup successful for \"#{i}\", but this indicates a docisbn mismatch, since it doesn't match existing isbn array"}
                        status_hash['docisbn_match_fail'] << i
                        if !status_hash['filename_isbn_lookup_ok']  #this is a showstopping error if we don't have a filename_isbn
                            status_hash['isbn_match_ok'] = false
                        end
                    end
                end
            end
        end
    }
else
    logger.info {"either 0 (or >10) good isbns found in status_hash['docisbn_string'] :( "}
end
# #################
# status_hash['doc_isbn_list'] = status_hash['doc_isbn_list'].uniq
# unique_isbns = status_hash['doc_isbn_list']
# if unique_isbns.empty? || unique_isbns.length > 10
#     logger.info {"either 0 (or >10) good isbns found in status_hash['docisbn_string'] :( "}
# else
#     logger.info {"#{unique_isbns.length} good isbns found in isbnstring; looking them up @ data warehouse: #{unique_isbns}"}
#     #now we lookup work ids for each isbn...
#     unique_isbns.each { |j|
#         thissql = exactSearchSingleKey(j, "EDITION_EAN")
#         myhash = runQuery(thissql)
#         if myhash.nil? or myhash.empty? or !myhash or myhash['book'].nil? or myhash['book'].empty? or !myhash['book']
#             logger.info {"isbn data-warehouse-lookup for manuscript isbn: #{j} failed."}
# 		status_hash['docisbn_lookup_fail'] << j
#         else
#             #and now we go get print isbn for each unique workid...
#             puts myhash
#             puts "work id: #{myhash['book']['WORK_ID']}"
#             thissql_B = exactSearchSingleKey(myhash['book']['WORK_ID'], "WORK_ID")
#             editionshash = runQuery(thissql_B)
#             unless editionshash.nil? or editionshash.empty? or !editionshash
#                 editionshash.each do |k, v|
#                     # find a print product if it exists
#                     if v['PRODUCTTYPE_DESC'] and v['PRODUCTTYPE_DESC'] == "Book"
#                         status_hash['pisbns'] << v['EDITION_EAN']
#                     end
#                 end
#             end
#         end
#     }
#     if status_hash['pisbns'].length > 1
#         logger.info {"too many pisbns found via doc_isbn lookup: marking pisbn_match false."}
#         status_hash['isbn_match_ok'] = false
#     elsif status_hash['pisbns'].length == 1
#         #perform bookinfo lookup on good pisbn!
#         logger.info {"found a good pisbn #{status_hash['pisbns'][0]} from doc_isbn workid(s), using that for lookups!"}
#         lookuplog = getbookinfo(status_hash['pisbns'][0],'pisbn_lookup_ok',status_hash,Val::Files.bookinfo_file)
# 	logger.info {lookuplog}
#     end
# end

if !status_hash['isbn_match_ok']          #fatal mismatch, delete bookinfo file!
    Mcmlln::Tools.deleteFile(Val::Files.bookinfo_file)
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
if !File.file?(Val::Files.bookinfo_file)
	   logger.info {"no bookinfo file present, will be skipping Validator macro"}
end
