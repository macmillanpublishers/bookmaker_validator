require 'fileutils'
require 'open3'
require 'json'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
alt_isbn_array = []
styled_isbns = []
unstyled_isbns = []

venv_dir = File.join(Bkmkr::Paths.scripts_dir, "biblio_api_consumer", ".venv")
BIBLIO_API_PYENV = [
  File.join(venv_dir, "Scripts", "python.exe"),
  File.join(venv_dir, "bin", "python.exe"),
  File.join(venv_dir, "bin", "python")
].find { |p| File.exist?(p) } || File.join(venv_dir, "bin", "python")

#---------------------  FUNCTIONS

def biblio_call(env, func, *args)
  out, err, status = Open3.capture3(BIBLIO_API_PYENV, '-m', 'biblio_api_consumer.biblio_api_lib', env, func, *args.map(&:to_s))
  return { 'status' => "python exited #{status.exitstatus}: #{err.lines.last.to_s.strip}", 'result' => {} } unless status.success?
  JSON.parse(out)
rescue JSON::ParserError => e
  { 'status' => "bad JSON from biblio_api_consumer: #{e.message}", 'result' => {} }
end

def lookup_ok?(r)
  !r.nil? && r['status'] == 'success' && !r['result'].to_h.empty?
end

# "not found" is a normal answer; anything else that isn't success is an api/system error
def record_api_error(status_hash, response, logger)
  s = response['status'].to_s
  return if s == 'success' || s.start_with?('ISBN not found')
  status_hash['dw_sql_err'] = s
  logger.warn {"biblio api error: #{s}"}
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


def normalize_isbns(list)
  Array(list).map { |i| i.to_s.gsub(/[^0-9X]/i, '') }.select { |i| i =~ /^97[89]\d{10}$/ }.uniq
end

def log_docisbn_lookup_fail(isbn, status_hash, logger)
  status_hash['docisbn_lookup_fail'] << isbn
  message = Val::Hashes.alertmessages_hash['warnings']['docisbn_lookup_fail']['message']
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", "#{message} #{status_hash['docisbn_lookup_fail'].uniq}")
  logger.info {"biblio lookup on docisbn \"#{isbn}\" failed"}
end

def checkdigit_ok?(isbn, whichisbn, status_hash, logger)
  return true if Vldtr::Tools.checkisbn(isbn)
  message = Val::Hashes.alertmessages_hash['warnings']["#{whichisbn}_checkdigit_fail"]['message']
  if whichisbn == 'filename_isbn'
    status_hash['filename_isbn']['checkdigit'] = false
    status_hash['filename_isbn_lookup_ok'] = false
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", "#{message} #{isbn}")
  else
    status_hash['docisbn_checkdigit_fail'] << isbn
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", "#{message} '#{isbn}'")
  end
  logger.warn {"checkdigit failed for #{whichisbn} \"#{isbn}\""}
  false
end

def report_docisbn_mismatch(isbn, status_hash, logger)
  return if status_hash['docisbn_match_fail'].include?(isbn)
  status_hash['docisbn_match_fail'] << isbn
  alldocisbns = (status_hash['docisbn_match_fail'] + status_hash['docisbns']).uniq
  logger.info {"\"#{isbn}\" is a valid isbn, but not an edition of this work: docisbn mismatch"}
  if status_hash['filename_isbn_lookup_ok']
    # good filename isbn wins anyway, just warn
    message = Val::Hashes.alertmessages_hash['warnings']['docisbn_match_fail']['message']
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", "#{message} #{alldocisbns}")
  else
    # no filename isbn: showstopper
    status_hash['isbn_match_ok'] = false
    status_hash['status'] = 'isbn error'
    message = Val::Hashes.alertmessages_hash['errors']['isbn_match_fail']['message']
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", "#{message} #{alldocisbns}")
  end
end

# same logic as old get_good_isbns: match against the work's editions, or (if no work yet) use as primary lookup,
# or (if work known) look it up to see if it's a true mismatch vs. a bad isbn
def process_doc_isbns(isbns, response, lookup_isbn, status_hash, logger)
  if isbns.empty? || isbns.length >= 10
    logger.info {"either 0 (or >10) good isbns found in doc isbn list :( "}
    return response, lookup_isbn
  end
  isbns.each do |i|
    editions = lookup_ok?(response) ? Array(response['result']['alt_edition_isbns']) : []
    if editions.include?(i)
      status_hash['docisbns'] << i unless status_hash['docisbns'].include?(i)
      next
    end
    next unless checkdigit_ok?(i, 'docisbn', status_hash, logger)

    if editions.empty?
      # no work found yet: this isbn becomes the primary lookup
      r = biblio_call('prod', 'egalleymakerCall', i)
      record_api_error(status_hash, r, logger)
      if lookup_ok?(r)
        logger.info {"docisbn \"#{i}\" checked out, no existing primary lookup isbn, using it for book info"}
        response, lookup_isbn = r, i
        status_hash['doc_isbn_lookup_ok'] = true
        status_hash['docisbns'] << i
      else
        log_docisbn_lookup_fail(i, status_hash, logger)
      end
    else
      # work already known & this isn't one of its editions: real isbn for another book, or junk?
      r = biblio_call('prod', 'isbnLookup', i)
      record_api_error(status_hash, r, logger)
      if lookup_ok?(r)
        report_docisbn_mismatch(i, status_hash, logger)
      else
        log_docisbn_lookup_fail(i, status_hash, logger)
      end
    end
  end
  return response, lookup_isbn
end

# same priority as old getbookinfo
def preferred_lookup_edition(lookup_isbn, filename_ok, styled_isbns, result, logger)
  pisbns = Array(result['print_isbns'])
  lead   = result['lead_edition'].to_s
  if filename_ok
    logger.info {"filename isbn is avail., using that as lookup_edition: #{lookup_isbn}."}
    lookup_isbn
  elsif (styled_print = styled_isbns.find { |i| pisbns.include?(i) })
    logger.info {"no (good) filename isbn, using styled print_isbn as lookup_edition: #{styled_print}."}
    styled_print
  elsif !lead.empty?
    logger.info {"no (good) filename isbn, no styled print_isbns, using lead_edition as lookup_edition: #{lead}."}
    lead
  elsif !pisbns.empty?
    logger.info {"no (good) filename isbn, no styled print_isbns, & no value for lead_edition, using a print_isbn as lookup_edition: #{pisbns[0]}."}
    pisbns[0]
  else
    logger.info {"no (good) filename isbn, no styled print_isbn, & no values for lead_edition or alt print_isbn, using 1st doc_isbn as lookup_edition: #{lookup_isbn}."}
    lookup_isbn
  end
end

def consolidateBiblioApiVars(result, lookup_isbn, lookup_edition, logger)
  not_found = ->(v) { v.to_s.strip.empty? ? 'not found' : v }
  book_hash = {
    production_editor:  not_found.(result['production_editor']),
    production_manager: not_found.(result['production_manager']),
    work_id:            result['work_id'],
    isbn:               lookup_isbn,
    title:              result['title'],
    author:             result['coverAuthor'],
    product_type:       result['product_type'],
    imprint:            result['imprint'],
    alt_isbns:          result['alt_edition_isbns'] || [],
    print_isbns:        result['print_isbns'] || [],
    lead_edition:       result['lead_edition'].to_s,
    lookup_edition:     lookup_edition
  }
  Vldtr::Tools.write_json(book_hash, Val::Files.bookinfo_file)
  logger.info {"bookinfo from #{lookup_isbn} OK- title: \"#{book_hash[:title]}\", author: \"#{book_hash[:author]}\", imprint: \"#{book_hash[:imprint]}\", product_type: \"#{book_hash[:product_type]}\""}
  return book_hash[:alt_isbns], book_hash[:print_isbns], book_hash[:lead_edition], result['epub_format'], (result['typeset_from'] || {'paper_copyedit' => ''})
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

biblio_api_response, lookup_isbn = nil, nil
styled_isbns, unstyled_isbns = [], []

# 1. filename isbn
isbn_pattern = /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
if Val::Doc.filename_normalized =~ isbn_pattern && Val::Doc.extension =~ /.doc($|x$)/
  filename_isbn = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
  status_hash['filename_isbn']['isbn'] = filename_isbn
  if checkdigit_ok?(filename_isbn, 'filename_isbn', status_hash, logger)
    status_hash['filename_isbn']['checkdigit'] = true
    response = biblio_call('prod', 'egalleymakerCall', filename_isbn)
    record_api_error(status_hash, response, logger)
    logger.info {"biblio lookup on filename isbn #{filename_isbn}: #{response['status']}"}
    if lookup_ok?(response)
      lookup_isbn, biblio_api_response = filename_isbn, response
    else
      status_hash['filename_isbn_lookup_ok'] = false
      message = Val::Hashes.alertmessages_hash['warnings']['filename_isbn_lookup_fail']['message']
      Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", "#{message} #{filename_isbn}")
    end
  end
elsif Val::Doc.filename_normalized !~ isbn_pattern
  logger.info {"no isbn in filename"}
  status_hash['filename_isbn_lookup_ok'] = false
end

# 2. doc isbns: styled first; unstyled only if no styled ones were usable and no filename isbn
if Val::Hashes.isbn_hash['completed'] == true && status_hash['password_protected'].to_s.empty?
  isbn_hash      = Mcmlln::Tools.readjson(Val::Files.isbn_file)
  styled_isbns   = normalize_isbns(isbn_hash['styled_isbns'])
  unstyled_isbns = normalize_isbns(isbn_hash['programatically_styled_isbns']) - styled_isbns
  biblio_api_response, lookup_isbn = process_doc_isbns(styled_isbns, biblio_api_response, lookup_isbn, status_hash, logger)
  if status_hash['docisbns'].empty? && !unstyled_isbns.empty? && status_hash['filename_isbn_lookup_ok'] == false
    logger.info {"no styled isbns from isbncheck.py, now trying out unstyled isbns"}
    biblio_api_response, lookup_isbn = process_doc_isbns(unstyled_isbns, biblio_api_response, lookup_isbn, status_hash, logger)
  end
else
  logger.info {"isbn_check.json not present or unavailable"}
end

# 3. pick lookup_edition (PM/PE + edition metadata come from it), re-call biblio if it differs
if lookup_ok?(biblio_api_response)
  result = biblio_api_response['result']
  lookup_edition = preferred_lookup_edition(lookup_isbn, status_hash['filename_isbn_lookup_ok'], styled_isbns, result, logger)
  if lookup_edition != lookup_isbn
    r = biblio_call('prod', 'egalleymakerCall', lookup_edition)
    record_api_error(status_hash, r, logger)
    if lookup_ok?(r)
      result = r['result']
    else
      logger.warn {"lookup on lookup_edition #{lookup_edition} failed (#{r['status']}), keeping data from #{lookup_isbn}"}
      lookup_edition = lookup_isbn
    end
  end
  alt_isbn_array, print_isbns, lead_edition, status_hash['epub_format'], status_hash['typeset_from'] = consolidateBiblioApiVars(result, lookup_isbn, lookup_edition, logger)
else
  logger.info {"no successful lookups for any isbn"}
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
      status_hash['epub_format'] = true
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
