require 'fileutils'
require 'nokogiri'

require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'

# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
alt_isbn_array = []

#---------------------  FUNCTIONS
#this function quick verifies an isbn: checkdigit, ean lookup.
def testisbn(isbn, whichisbn, status_hash)
    lookup, loginfo = false, ''
    if Vldtr::Tools.checkisbn(isbn)
        if whichisbn == 'filename_isbn' then status_hash['filename_isbn']['checkdigit'] = true end
        thissql_A = exactSearchSingleKey(isbn, "EDITION_EAN")
        myhash_A = runQuery(thissql_A)
        if myhash_A.nil? or myhash_A.empty? or !myhash_A or myhash_A['book'].nil? or myhash_A['book'].empty? or !myhash_A['book']
            loginfo = "data warehouse lookup on #{whichisbn} \"#{isbn}\" failed, setting status to false"
            if whichisbn == 'filename_isbn'
              status_hash['filename_isbn_lookup_ok'] = false
              # log to alert json as warning
              alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['filename_isbn_lookup_fail']} #{status_hash['filename_isbn']['isbn']}"
              Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
            end
            if whichisbn == 'docisbn'
              status_hash['docisbn_lookup_fail'] << isbn
              # log to alert json as warning
              alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbnlookup_msg']} #{status_hash['docisbn_lookup_fail'].uniq}"
              Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
            end
        else  #isbn checks out
            lookup = true
        end
    else  #checkdigit failed
        if whichisbn == 'filename_isbn'
            status_hash['filename_isbn']['checkdigit'] = false
            # log to alerts json
            alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['filename_isbn_checkdigit_fail']} #{status_hash['filename_isbn']['isbn']}"
            Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
            # still set larger category status as false in case we still have dependencies
            status_hash['filename_isbn_lookup_ok'] = false
        end
        if whichisbn == 'docisbn'
            status_hash['docisbn_checkdigit_fail'] << isbn
            # log to alerts json
            alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbn_checkdigit_fail']} #{status_hash['docisbn_checkdigit_fail'].uniq}"
            Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
        end
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
  			pm_name = 'not found'
  			loginfo = "no pm found for this EDITION_EAN\n"
		else
  			pm_name = myhash_C['book']['PERSON_REALNAME'][0]
		end
 		thissql_D = personSearchSingleKey(lookup_isbn, "EDITION_EAN", "Production Editor")
    myhash_D = runPeopleQuery(thissql_D)
    if myhash_D.nil? or myhash_D.empty? or !myhash_D or myhash_D['book'].nil? or myhash_D['book'].empty? or !myhash_D['book']
  			pe_name = 'not found'
  			loginfo = "#{loginfo}no pe found for this EDITION_EAN\n"
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
    alt_isbn_array = []
    epub_format = false
    thissql_E = exactSearchSingleKey(work_id, "WORK_ID")
    editionshash_B = runQuery(thissql_E)
    editionshash_B.each { |book, hash|
      hash.each { |k,v|
        if k == 'EDITION_EAN' then alt_isbn_array << v end
        if k == 'FORMAT_LONGNAME'
            if v == 'EPUB' then epub_format = true end
        end
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

	  return loginfo, alt_isbn_array, epub_format
end

def typeset_from_check(typesetfrom_file, isbn_array)
    file_xml = File.open(typesetfrom_file) { |f| Nokogiri::XML(f)}
    msword_copyedit = false
    isbn_array.each { |isbn|
      	next if isbn.empty?
        check = file_xml.xpath("//record[edition_eanisbn13=#{isbn}]/impression_typeset_from").to_s
        if check =~ /Copyedited Word File/m || check =~ /Word Styles File/m
            msword_copyedit = true
        end
    }
    return msword_copyedit
end

def lookup_backup_contact(pm_or_pe, staff_hash, submitter_mail, staff_defaults_hash, status)   #no name associated in biblio, lookup backup PM/PE via submitter division
  mail, newstatus = 'not found', status
  for i in 0..staff_hash.length - 1
    if submitter_mail.downcase == staff_hash[i]['email'].downcase
      submitter_div = staff_hash[i]['division']
      if staff_defaults_hash[submitter_div]
    		mail = staff_defaults_hash[submitter_div][pm_or_pe]
    		name = staff_defaults_hash[submitter_div]["#{pm_or_pe}_name"]
      else
    		newstatus = "#{newstatus}, and \'#{submitter_div}\' not present in defaults.json"
        name, mail = 'Workflows', 'workflows@macmillan.com'
      end
    end
  end
  if mail == 'not found'   #this means dropbox api failed, or submitter is not in staff.json just sentall emails to Workflows
    newstatus = "#{newstatus}, and submitter email not in staff.json"
    name, mail = 'Workflows', 'workflows@macmillan.com'
    # alert Worfklows that a fallback lookup failed:
     body = <<MESSAGE_END
Subject: Alert - egalleymaker staff.json lookup failed

Please note, egalleymaker may still be successfully running for this title; this error only affects email notifications
(all notifications should now be being sent to workflows@macmillan.com)
------
ERROR:
#{pm_or_pe} lookup in biblio failed, & fallback lookup of division head based on submitter's email failed as well:
- submitter email not in staff.json
------
INFO:
time: #{Time.now}
file: #{Val::Doc.filename_normalized}
submitter email: #{submitter_mail}
MESSAGE_END
    message = Vldtr::Mailtexts.generic('Worfklows','workflows@macmillan.com',"#{body}")
    unless File.file?(Val::Paths.testing_value_file)
      Vldtr::Tools.sendmail("#{message}",'workflows@macmillan.com','workflows@macmillan.com')
    end
  end
  return mail, name, newstatus
end

def staff_lookup(name, pm_or_pe, staff_hash, submitter_mail, staff_defaults_hash)
  status, newname, mail = '', name, 'not found'
  if newname == 'not found'
    status = 'not in biblio'
    mail, newname, status = lookup_backup_contact(pm_or_pe, staff_hash, submitter_mail, staff_defaults_hash, status)
    # adding to alerts.json:
    if pm_or_pe == "PM"
      msg_detail = "\'#{contacts_hash['production_manager_name']}\'/\'#{contacts_hash['production_manager_email']}\'"
    elsif pm_or_pe == "PE"
      msg_detail = "\'#{contacts_hash['production_editor_name']}\'/\'#{contacts_hash['production_editor_email']}\'"
    end
    alertstring = "#{Val::Hashes.alertmessages_hash['warnings']["#{pm_or_pe.downcase}_lookup_fail"]}: #{msg_detail}"
    Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
  elsif newname.empty?
    status = 'no bookinfo file?'
    mail, newname, status = lookup_backup_contact(pm_or_pe, staff_hash, submitter_mail, staff_defaults_hash, status)
  else
    status = "#{pm_or_pe} name in biblio"
    for i in 0..staff_hash.length - 1
      if newname.downcase == "#{staff_hash[i]['firstName'].downcase} #{staff_hash[i]['lastName'].downcase}"
        mail = staff_hash[i]['email']
        status = "#{status}, found email in staff.json"
      end
    end
    if mail == 'not found'    #this means pm/pe's email was not in staff.json
      status = "#{status}, their email is not in staff.json"
      newname, mail = 'Workflows', 'workflows@macmillan.com'
      # alert Worfklows that a PM/PE email lookup failed:
      body = <<MESSAGE_END
Subject: Alert - egalleymaker staff.json lookup failed

Please note, egalleymaker may still be successfully running for this title; this error only affects email notifications
(all notifications should now be being sent to workflows@macmillan.com)
---------
ERROR:
- #{pm_or_pe} Data Warehouse lookup succeeded, but #{pm_or_pe}'s email address is not in staff.json
---------
INFO:
time: #{Time.now}
file: #{Val::Doc.filename_normalized}
#{pm_or_pe} name: #{name}
submitter email: #{submitter_mail}
MESSAGE_END
      message = Vldtr::Mailtexts.generic('Worfklows','workflows@macmillan.com',"#{body}")
      unless File.file?(Val::Paths.testing_value_file)
        Vldtr::Tools.sendmail("#{message}",'workflows@macmillan.com','workflows@macmillan.com')
      end
    end
  end
  return mail, newname, status
end

#--------------------- RUN
#load key jsons, create some local vars
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
else
	logger.info {"status.json not present or unavailable"}
  status_hash = {}
end
status_hash['filename_isbn'] = {"isbn"=> ''}
status_hash['filename_isbn']['checkdigit'] = ''
status_hash['filename_isbn_lookup_ok'] = true
status_hash['doc_isbn_lookup_ok'] = ''
status_hash['docisbns'] = []
status_hash['docisbn_checkdigit_fail'] = []
status_hash['docisbn_lookup_fail'] = []
status_hash['docisbn_match_fail'] = []
status_hash['isbn_match_ok'] = true
status_hash['pe_lookup'] = ''
status_hash['pm_lookup'] = ''

#read in out contacts.json so we can update it with pe/pm:
if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
else
	contacts_hash = {}
	contacts_hash['submitter_email'] = 'workflows@macmillan.com'
  contacts_hash['submitter_name'] = ''
	logger.info {"contacts json not found?"}
end

#try lookup on filename isbn
if Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && Val::Doc.extension =~ /.doc($|x$)/ &&	status_hash['password_protected'] == false && Val::Hashes.isbn_hash['completed'] == true
    filename_isbn = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    status_hash['filename_isbn']["isbn"] = filename_isbn
    testlog, testlookup = testisbn(filename_isbn, "filename_isbn", status_hash)
    if !testlog.empty? then logger.info {"#{testlog}"} end
    if testlookup == true
        logger.info {"isbn \"#{filename_isbn}\" checked out, proceeding with getting book info"}
        lookuplog, alt_isbn_array, status_hash['epub_format'] = getbookinfo(filename_isbn,'filename_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file)
		    if !lookuplog.empty? then logger.info {"#{lookuplog}"} end
    end
elsif !Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    logger.info {"no isbn in filename"}
    # this value is important b/c it helps us determine 'nogoodisbn' in mailer for isbnerror
    status_hash['filename_isbn_lookup_ok'] = false
end

#get isbns from json, verify checkdigit, create array of good isbns
if Val::Hashes.isbn_hash['completed'] == true && status_hash['password_protected'] == false
  	isbn_hash = Mcmlln::Tools.readjson(Val::Files.isbn_file)
  	docisbn_array = isbn_hash['isbn']['list']
    if docisbn_array.length < 10 && !docisbn_array.empty?
        docisbn_array.each { |i|
            i.gsub!(/-/,'')
            if i =~ /97(8|9)[0-9]{10}/
                if alt_isbn_array.include?(i)   #if it matches a filename isbn already
                    status_hash['docisbns'] << i
                else
                    testlog_b, testlookup_b = testisbn(i, "docisbn", status_hash)      #quick check the isbn
                    if !testlog_b.empty? then logger.info {testlog_b} end
                    if testlookup_b == true
                        if alt_isbn_array.empty?            #if no isbn array exists yet, this one will be thr primary lookup for bookinfo
                            logger.info {"docisbn \"#{i}\" checked out, no existing primary lookup isbn, proceeding with getting book info"}
                            lookuplog_b, alt_isbn_array, status_hash['epub_format'] = getbookinfo(i,'doc_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file)
                    		    if !lookuplog_b.empty? then logger.info {lookuplog_b} end
                            status_hash['docisbns'] << i
                        else            #since an isbn array exists that we don't match, we have a mismatch;
                            logger.info {"lookup successful for \"#{i}\", but this indicates a docisbn mismatch, since it doesn't match existing isbn array"}
                            status_hash['docisbn_match_fail'] << i
                            # log to alerts.json as warning
                            alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbnmatch_msg']} #{status_hash['docisbn_match_fail'].uniq}"
                            Vldtr::Tools.log_alert_to_json(alerts_json, "warning", alertstring)
                            if !status_hash['filename_isbn_lookup_ok']  #this is a showstopping error if we don't have a filename_isbn
                                status_hash['isbn_match_ok'] = false
                                # log to alerts.json as error
                                alertstring = "#{Val::Hashes.alertmessages_hash['errors']['isbn_match_fail']} #{status_hash['docisbns']}, #{status_hash['docisbn_match_fail']}"
                                Vldtr::Tools.log_alert_to_json(alerts_json, "error", alertstring)
                                # this helps determine recipients of err mail:
                                status_hash['status'] = 'isbn error'
                            end
                        end
                    end
                end
            end
        }
    else
        logger.info {"either 0 (or >10) good isbns found in status_hash['docisbn_string'] :( "}
    end
else
  	logger.info {"isbn_check.json not present or unavailable, isbn_check "}
end

if !status_hash['isbn_match_ok']          #fatal mismatch, delete bookinfo file!
    Mcmlln::Tools.deleteFile(Val::Files.bookinfo_file)
end

#get info from bookinfo.json, do pe & pm lookups (& setting up handling for cc's)
if File.file?(Val::Files.bookinfo_file)
  bookinfo_hash = Mcmlln::Tools.readjson(Val::Files.bookinfo_file)
  pm_name = bookinfo_hash['production_manager']
  pe_name = bookinfo_hash['production_editor']
  logger.info {"retrieved from book_info.json- pe_name:\"#{pe_name}\", pm_name:\"#{pm_name}\""}
else
  pm_name, pe_name = '',''
end

#read in our static pe/pm json
staff_hash = Mcmlln::Tools.readjson(Val::Files.staff_emails)
staff_defaults_hash = Mcmlln::Tools.readjson(Val::Files.imprint_defaultPMs)

#lookup mails & status for PE's and PM's, add to submitter_file json
contacts_hash['production_manager_email'], contacts_hash['production_manager_name'], status_hash['pm_lookup'] = staff_lookup(pm_name, 'PM', staff_hash, contacts_hash['submitter_email'], staff_defaults_hash)
contacts_hash['production_editor_email'], contacts_hash['production_editor_name'], status_hash['pe_lookup'] = staff_lookup(pe_name, 'PE', staff_hash, contacts_hash['submitter_email'], staff_defaults_hash)
Vldtr::Tools.write_json(contacts_hash, Val::Files.contacts_file)
logger.info {"retrieved info--  PM mail:\"#{contacts_hash['production_manager_email']}\", status: \'#{status_hash['pm_lookup']}\'.  PE mail:\"#{contacts_hash['production_editor_email']}\", status: \'#{status_hash['pe_lookup']}\'"}

if !File.file?(Val::Files.bookinfo_file)
	   logger.info {"no bookinfo file present, will be skipping Validator macro"}
     status_hash['msword_copyedit'], status_hash['epub_format'] = '', ''
else
    #check for paper_copyedits
    status_hash['msword_copyedit'] = typeset_from_check(Val::Files.typesetfrom_file, alt_isbn_array)
    if status_hash['msword_copyedit'] == false
      logger.info {"This appears to be a paper_copyedit, will skip validator macro"}
      # log as notice to alerts.json
      Vldtr::Tools.log_alert_to_json(alerts_json, "notice", Val::Hashes.alertmessages_hash["notices"]["paper_copyedit"])
    end
    #log re: fixed layout:
    if status_hash['epub_format'] == false
      logger.info {"This looks like fixed layout, will skip validator macro"}
      # log as notice to alerts.json
      Vldtr::Tools.log_alert_to_json(alerts_json, "notice", Val::Hashes.alertmessages_hash["notices"]["fixed_layout"])
    end
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
