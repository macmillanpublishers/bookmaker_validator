require 'fileutils'
# require 'nokogiri'

require_relative '../utilities/oraclequery.rb'
require_relative '../utilities/isbn_finder.rb'
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
    if Vldtr::Tools.checkisbn(isbn) and status_hash['dw_sql_err'] == ''
        if whichisbn == 'filename_isbn' then status_hash['filename_isbn']['checkdigit'] = true end
        thissql_A = exactSearchSingleKey(isbn, "EDITION_EAN")
        myhash_A, querystatus = runQuery(thissql_A)
        if querystatus != 'success'
          status_hash['dw_sql_err'] = querystatus
          logger.warn {"exactSearchSingleKey dw_lookup encountered error: #{querystatus}"}
        end
        if myhash_A.nil? or myhash_A.empty? or !myhash_A or myhash_A['book'].nil? or myhash_A['book'].empty? or !myhash_A['book']
            loginfo = "data warehouse lookup on #{whichisbn} \"#{isbn}\" failed, setting status to false"
            if whichisbn == 'filename_isbn'
              status_hash['filename_isbn_lookup_ok'] = false
              # log to alert json as warning
              alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['filename_isbn_lookup_fail']['message']} #{status_hash['filename_isbn']['isbn']}"
              Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
            end
            if whichisbn == 'docisbn'
              status_hash['docisbn_lookup_fail'] << isbn
              # log to alert json as warning
              alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbn_lookup_fail']['message']} #{status_hash['docisbn_lookup_fail'].uniq}"
              Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
            end
        else  #isbn checks out
            lookup = true
        end
    else  #checkdigit failed
        if whichisbn == 'filename_isbn'
            status_hash['filename_isbn']['checkdigit'] = false
            # log to alerts json
            alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['filename_isbn_checkdigit_fail']['message']} #{status_hash['filename_isbn']['isbn']}"
            Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
            # still set larger category status as false in case we still have dependencies
            status_hash['filename_isbn_lookup_ok'] = false
        end
        if whichisbn == 'docisbn'
            status_hash['docisbn_checkdigit_fail'] << isbn
            # log to alerts json
            alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbn_checkdigit_fail']['message']} '#{isbn}'"
            Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
        end
        loginfo = "checkdigit failed for #{whichisbn} \"#{isbn}\""
    end
    return loginfo, lookup
end

#this function takes our good isbn, gathers info and writes it to file.
def getbookinfo(lookup_isbn, hash_lookup_string, status_hash, bookinfo_file, logger, styled_isbns = [])
    # get typeset_from & lead_edition known good lookup_isbn (print_isbn is a fallback for lead_edition)
    alt_isbn_array, lead_edition, print_isbns, typeset_from, epub_format, querystatus = getLeadEdition_TypesetFrom(lookup_isbn)
    logger.info {"alt_isbn_array: #{alt_isbn_array}, lead_edition: #{lead_edition}, print_isbns: #{print_isbns}, typeset_from: #{typeset_from}, epub_format: #{epub_format}, styled_isbns: #{styled_isbns}"}
    if querystatus != 'success'
      status_hash['dw_sql_err'] = querystatus
      logger.warn {"getLeadEdition_TypesetFrom dw_lookup encountered error: #{querystatus}"}
    end
    # determine what isbn to use for lookup_edition:
    lookup_edition = ''
    if status_hash['filename_isbn_lookup_ok'] == true # <--indicates this is a filename isbn
      lookup_edition = lookup_isbn
      logger.info {"filename isbn is avail., using that as lookup_edition: #{lookup_edition}."}
    # next prefer a styled_isbn that is a print_isbn
    elsif !styled_isbns.empty? and !print_isbns.empty?
      for styled_isbn in styled_isbns
        if print_isbns.include?(styled_isbn)
          lookup_edition = styled_isbn
          logger.info {"no (good) filename isbn, using styled print_isbn as lookup_edition: #{lookup_edition}."}
          break
        end
      end
    end
    # if the above two tests didn't turn up a lookup_edition, go on down the list
    if lookup_edition == ''
      if !lead_edition.empty?
        lookup_edition = lead_edition
        logger.info {"no (good) filename isbn, no styled print_isbns, using lead_edition as lookup_edition: #{lookup_edition}."}
      elsif !print_isbns.empty?
        lookup_edition = print_isbns[0]
        logger.info {"no (good) filename isbn, no styled print_isbns, & no value for lead_edition, using a print_isbn as lookup_edition: #{lookup_edition}."}
      else
        lookup_edition = lookup_isbn
        logger.info {"no (good) filename isbn, no styled print_isbn, & no values for lead_edition or alt print_isbn, using 1st doc_isbn as lookup_edition: #{lookup_edition}."}
      end
    end

    #now do lookups for PM & PE
    if status_hash['dw_sql_err'] == ''
      thissql_C = personSearchSingleKey(lookup_edition, "EDITION_EAN", "Production Manager")
      myhash_C, querystatus = runPeopleQuery(thissql_C)
      if querystatus != 'success'
        status_hash['dw_sql_err'] = querystatus
        logger.warn {"runPeopleQuery dw_lookup encountered error: #{querystatus}"}
      end
    else
      myhash_C = {}
      logger.warn {"skipping pm lookup due to prev dw lookup err"}
    end
		if myhash_C.nil? or myhash_C.empty? or !myhash_C or myhash_C['book'].nil? or myhash_C['book'].empty? or !myhash_C['book']
  			pm_name = 'not found'
  			logger.info {"no pm found for this EDITION_EAN"}
		else
  			pm_name = myhash_C['book']['PERSON_REALNAME'][0]
		end

    if status_hash['dw_sql_err'] == ''
      thissql_D = personSearchSingleKey(lookup_edition, "EDITION_EAN", "Production Editor")
      myhash_D, querystatus = runPeopleQuery(thissql_D)
      if querystatus != 'success'
        status_hash['dw_sql_err'] = querystatus
        logger.warn {"runPeopleQuery dw_lookup encountered error: #{querystatus}"}
      end
    else
      myhash_D = {}
      logger.warn {"skipping pe lookup due to prev dw lookup err"}
    end

    if myhash_D.nil? or myhash_D.empty? or !myhash_D or myhash_D['book'].nil? or myhash_D['book'].empty? or !myhash_D['book']
  			pe_name = 'not found'
  			logger.info {"no pe found for this EDITION_EAN"}
		else
  			pe_name = myhash_D['book']['PERSON_REALNAME'][0]
		end

    # do lookup on lookup_edition for metainfo
    if status_hash['dw_sql_err'] == ''
      thissql_F = exactSearchSingleKey(lookup_edition, "EDITION_EAN")
      myhash_F, querystatus = runQuery(thissql_F)
      if querystatus != 'success'
        status_hash['dw_sql_err'] = querystatus
        logger.warn {"runQuery dw_lookup encountered error: #{querystatus}"}
      end
    else
      myhash_F = {}
      logger.warn {"skipping lookup_edition lookup due to prev dw lookup err"}
    end

    #write to hash
    book_hash = {}
    book_hash.merge!(production_editor: pe_name)
    book_hash.merge!(production_manager: pm_name)
    book_hash.merge!(work_id: myhash_F['book']['WORK_ID'])
    book_hash.merge!(isbn: lookup_isbn)
    book_hash.merge!(title: myhash_F['book']['WORK_COVERTITLE'])
    book_hash.merge!(author: myhash_F['book']['WORK_COVERAUTHOR'])
    book_hash.merge!(product_type: myhash_F['book']['PRODUCTTYPE_DESC'])
    book_hash.merge!(imprint: myhash_F['book']['IMPRINT_DISPLAY'])
    book_hash.merge!(alt_isbns: alt_isbn_array)
    book_hash.merge!(print_isbns: print_isbns)
    book_hash.merge!(lead_edition: lead_edition)
    book_hash.merge!(lookup_edition: lookup_edition)

    #write json:
    Vldtr::Tools.write_json(book_hash, bookinfo_file)

    status_hash[hash_lookup_string] = true
		logger.info {"bookinfo from #{lookup_isbn} OK- title: \"#{book_hash[:title]}\", author: \"#{book_hash[:author]}\", imprint: \"#{book_hash[:imprint]}\", product_type: \"#{book_hash[:product_type]}\""}

	  return alt_isbn_array, epub_format, typeset_from
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
    # alert Workflows that a fallback lookup failed:
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
    message = Vldtr::Mailtexts.generic('Workflows','workflows@macmillan.com',"#{body}")
    if File.file?(Val::Paths.testing_value_file)
      message += "\n\nThis message sent from STAGING SERVER"
    end
    Vldtr::Tools.sendmail("#{message}",'workflows@macmillan.com','workflows@macmillan.com')
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
      msg_detail = "\'#{newname}\'/\'#{mail}\'"
    elsif pm_or_pe == "PE"
      msg_detail = "\'#{newname}\'/\'#{mail}\'"
    end
    alertstring = "#{Val::Hashes.alertmessages_hash['warnings']["#{pm_or_pe.downcase}_lookup_fail"]['message']}: #{msg_detail}"
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
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
      # alert Workflows that a PM/PE email lookup failed:
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
      message = Vldtr::Mailtexts.generic('Workflows','workflows@macmillan.com',"#{body}")
      if File.file?(Val::Paths.testing_value_file)
        message += "\n\nThis message sent from STAGING SERVER"
      end
      Vldtr::Tools.sendmail("#{message}",'workflows@macmillan.com','workflows@macmillan.com')
    end
  end
  return mail, newname, status
end

def get_good_isbns(isbns_from_file, alt_isbn_array, status_hash, styled_isbns, logger)
  if isbns_from_file.length < 10 && !isbns_from_file.empty?
      isbns_from_file.each { |i|
          i.gsub!(/-/,'')
          if i =~ /97(8|9)[0-9]{10}/
              if alt_isbn_array.include?(i)   #if it matches a filename isbn / previously detected isbn already
                  status_hash['docisbns'] << i
              else
                  testlog_b, testlookup_b = testisbn(i, "docisbn", status_hash)      #quick check the isbn
                  if !testlog_b.empty? then logger.info {testlog_b} end
                  if testlookup_b == true
                      if alt_isbn_array.empty?            #if no isbn array exists yet, this one will be thr primary lookup for bookinfo
                          logger.info {"docisbn \"#{i}\" checked out, no existing primary lookup isbn, proceeding with getting book info"}
                          alt_isbn_array, status_hash['epub_format'], status_hash['typeset_from'] = getbookinfo(i,'doc_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file,logger,styled_isbns)
                          # if !lookuplog_b.empty? then logger.info {lookuplog_b} end
                          status_hash['docisbns'] << i
                      else            #since an isbn array exists that we don't match, we have a mismatch;
                          logger.info {"lookup successful for \"#{i}\", but this indicates a docisbn mismatch, since it doesn't match existing isbn array"}
                          if !status_hash['docisbn_match_fail'].include?(i) # to avoid re-processing for the same isbn repeatedly
                              status_hash['docisbn_match_fail'] << i
                              alldocisbns = status_hash['docisbn_match_fail'] + status_hash['docisbns']
                              if !status_hash['filename_isbn_lookup_ok']  #in this context this is a showstopping error if we don't have a filename_isbn
                                  status_hash['isbn_match_ok'] = false
                                  # log to alerts.json as error
                                  alertstring = "#{Val::Hashes.alertmessages_hash['errors']['isbn_match_fail']['message']} #{alldocisbns.uniq}"
                                  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", alertstring)
                                  # this helps determine recipients of err mail:
                                  status_hash['status'] = 'isbn error'
                              else
                                  # if we have a good filename isbn we prefer that anyways, just log to alerts.json as warning
                                  alertstring = "#{Val::Hashes.alertmessages_hash['warnings']['docisbn_match_fail']['message']} #{alldocisbns.uniq}"
                                  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", alertstring)
                              end
                          end
                      end
                  end
              end
          end
      }
  else
      logger.info {"either 0 (or >10) good isbns found in status_hash['docisbn_string'] :( "}
  end
  return alt_isbn_array, status_hash
end

# def typeset_from_check(typesetfrom_file, isbn_array)
#   file_xml = File.open(typesetfrom_file) { |f| Nokogiri::XML(f)}
#   msword_copyedit = false
#   isbn_array.each { |isbn|
#   	next if isbn.empty?
#     check = file_xml.xpath("//record[edition_eanisbn13=#{isbn}]/impression_typeset_from").to_s
#     if check =~ /Copyedited Word File/m || check =~ /Word Styles File/m
#       msword_copyedit = true
#     end
#   }
#   return msword_copyedit
# end

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
status_hash['dw_sql_err'] = ''

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
if Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/ && Val::Doc.extension =~ /.doc($|x$)/ &&	status_hash['password_protected'].empty? && Val::Hashes.isbn_hash['completed'] == true
    filename_isbn = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    status_hash['filename_isbn']["isbn"] = filename_isbn
    testlog, testlookup = testisbn(filename_isbn, "filename_isbn", status_hash)
    if !testlog.empty? then logger.info {"#{testlog}"} end
    if testlookup == true
        logger.info {"isbn \"#{filename_isbn}\" checked out, proceeding with getting book info"}
        alt_isbn_array, status_hash['epub_format'], status_hash['typeset_from'] = getbookinfo(filename_isbn,'filename_isbn_lookup_ok',status_hash,Val::Files.bookinfo_file, logger)
		    # if !lookuplog.empty? then logger.info {"#{lookuplog}"} end
    end
elsif Val::Doc.filename_normalized !~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    logger.info {"no isbn in filename"}
    # this value is important b/c it helps us determine 'nogoodisbn' in mailer for isbnerror
    status_hash['filename_isbn_lookup_ok'] = false
end

#get isbns from json, verify checkdigit, create array of good isbns
if Val::Hashes.isbn_hash['completed'] == true && status_hash['password_protected'].empty?
  	isbn_hash = Mcmlln::Tools.readjson(Val::Files.isbn_file)
  	unstyled_isbns = isbn_hash['programatically_styled_isbns']
    styled_isbns = isbn_hash['styled_isbns']
    alt_isbn_array, status_hash = get_good_isbns(styled_isbns, alt_isbn_array, status_hash, styled_isbns, logger)
    if status_hash['docisbns'].empty? && !unstyled_isbns.empty? && status_hash['filename_isbn_lookup_ok'] == false
      logger.info {"no styled isbns from isbncheck.py, now trying out unstyled isbns"}
      alt_isbn_array, status_hash = get_good_isbns(unstyled_isbns, alt_isbn_array, status_hash, styled_isbns, logger)
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
 status_hash['typeset_from'], status_hash['msword_copyedit'], status_hash['epub_format'] = {}, '', ''
else
  # check for paper_copyedits, allow it to pass regardless when using Val::Resources.testisbn
  status_hash['msword_copyedit'] = true
  if status_hash['typeset_from'].keys.include?("paper_copyedit")
    # make sure none of this work's ISBN's are listed in paper_copyedit exclusions
    unless (alt_isbn_array & Val::Hashes.papercopyedit_exceptions_hash).any?
      logger.info {"This appears to be a paper_copyedit, will skip validator macro"}
      status_hash['msword_copyedit'] = false # < -- we have dependencies on this var in several other scripts .
      # log as notice to alerts.json
      Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "notice", Val::Hashes.alertmessages_hash["notices"]["paper_copyedit"]['message'])
    else
      logger.info {"This looks-up as a paper_copyedit, but isbn is listed in 'papercopyedit_exceptions.json', so continuing as with an MSWord_Copyedit"}
      status_hash['test_isbn'] = true
    end
  end
  #log re: fixed layout:
  if status_hash['epub_format'] == false
    logger.info {"This looks like fixed layout, will skip validator macro"}
    # log as notice to alerts.json
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "notice", Val::Hashes.alertmessages_hash["notices"]["fixed_layout"]['message'])
  end
  if !status_hash['epub_format'] == false && !status_hash['msword_copyedit'] == false
    logger.info {"Neither fixed-layout nor paper_copyedit detected, moving on!"}
  end
end

# (moved form mailer) this error might as well stay / get logged here, since it depends on other isbn fields that are more easily reviewed post-lookups
if status_hash['docisbns'].empty? && !status_hash['filename_isbn_lookup_ok'] && status_hash['isbn_match_ok']
	# nogoodisbn = true
  # log to alerts.json as error
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash['errors']['no_good_isbn']['message'])
	status_hash['status'] = 'isbn error'
end
if status_hash['dw_sql_err'] != ''
  # log to alerts.json as error
  alertstring = "#{Val::Hashes.alertmessages_hash['errors']['dw_sql_err']['message']} #{status_hash['dw_sql_err']}"
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", alertstring)
	status_hash['status'] = 'data-warehouse lookup error'
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
