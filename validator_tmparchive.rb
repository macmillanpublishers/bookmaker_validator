require 'fileutils'
require 'open3'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
macro_name = "Validator.IsbnSearch"
file_recd_txt = File.read(File.join(Val::Paths.mailer_dir,'file_received.txt'))
isbncheck_py = "validator_isbncheck.py"
isbncheck_py_path = File.join(Val::Paths.bookmaker_scripts_dir, 'sectionstart_converter', 'xml_docx_stylechecks', isbncheck_py)
get_custom_doc_prop_py = File.join(Val::Paths.bookmaker_scripts_dir, "bookmaker_addons", "getCustomDocProp.py")
version_doc_property_name = 'Version'
bypass_validate_doc_property_name = 'bypass_validate'
sectionstart_template_version = '5.0'
rsuite_template_version = '6.0'

contacts_hash = {}
contacts_hash['ebooksDept_submitter'] = false
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
status_hash['password_protected'] = ''
user_email = ''
status_hash['doctemplate_version'] = ''

#---------------------  METHODS
def set_submitter_info(logger,user_email,user_name,contacts_hash,status_hash)
  if user_email == '' or user_email == 'unavailable'
    status_hash['api_ok'] = false
    user_email = 'workflows@macmillan.com'
    user_name = 'Workflows'
    logger.info {"#{Val::Doc.runtype} api may have failed, not finding submitter metadata"}
    # adding to alerts.json:
    Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "warning", Val::Hashes.alertmessages_hash["warnings"]["api"]["message"])
  else
    #check to see if submitter is in ebooks dept.:
    staff_hash = Mcmlln::Tools.readjson(Val::Files.staff_emails)  		#read in our static pe/pm json
    for i in 0..staff_hash.length - 1
      if user_email.downcase == "#{staff_hash[i]['email'].downcase}"
        if "#{staff_hash[i]['division']}" == 'Ebooks' || "#{staff_hash[i]['division']}" == 'Workflow'
          contacts_hash['ebooksDept_submitter'] = true
          logger.info {"#{user_name} is a member of ebooks or Workflow dept, flagging that to edit user comm. addressees"}
          # log as notice to alerts.json
          alertstring = "All email communications normally slated for PM or PE are being redirected to a submitter from Ebooks or Workflow dept."
          Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "notice", alertstring)
        end
      end
    end
  end
  #writing user info to contacts json
  contacts_hash.merge!(submitter_name: user_name)
  contacts_hash.merge!(submitter_email: user_email)
  Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
  logger.info {"file submitter determined, display name: \"#{user_name}\", email: \"#{user_email}\", written to contacts.json"}
end

def nondoc(logger,status_hash)
  status_hash['docfile'] = false
  logger.info {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
  # logging err directly to json:
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["not_a_docfile"]["message"])
  status_hash['status'] = 'not a .doc(x)'
end
def convertDocToDocxPSscript(logger, doc_or_docx_workingfile)
  `#{Val::Resources.powershell_exe} "#{File.join(Val::Paths.scripts_dir, 'save_doc_as_docx.ps1')} '#{doc_or_docx_workingfile}'"`
rescue => e
  logger.info {"Error converting to .docx: #{e}"}
end

def movedoc(logger)
  # setting a var for the workingfile before its converted to .docx
  doc_or_docx_workingfile = File.join(Val::Paths.tmp_dir, Val::Doc.filename_normalized)
  #if its a .doc(x) lets go ahead and move it to tmpdir, keep a pristing copy in subfolder
  FileUtils.mkdir_p Val::Paths.tmp_original_dir
  Mcmlln::Tools.moveFile(Val::Doc.input_file_untag_chars, Val::Files.original_file)
  # constructing 'working' destination since the new 'working' file might still be a .doc at this point
  Mcmlln::Tools.copyFile(Val::Files.original_file, doc_or_docx_workingfile)
  if Val::Doc.filename_split == Val::Doc.filename_normalized
    logger.info {"moved #{Val::Doc.filename_split} to tmpdir"}
  else
    logger.info {"renamed \"#{Val::Doc.filename_split}\" to \"#{Val::Doc.filename_normalized}\" and moved to tmpdir "}
  end
  # if .doc, save up to .docx
  if Val::Doc.extension.match(/.doc$/)
    logger.info {"working file is a .doc (#{Val::Doc.filename_normalized}), attempting to save as a .docx"}
    convertDocToDocxPSscript(logger, doc_or_docx_workingfile)
    if File.file?(Val::Files.working_file)
      logger.info {".doc successfully saved as .docx (#{Val::Files.working_file})"}
    else
      logger.info {".doc NOT successfully saved as .docx :("}
    end
  end
end

# returns false if v1 is empty, nil, has bad characters, or is less than v2
def versionCompare(v1, v2, logger)
  # eliminate leading 'v' if present
  if v1[0] == 'v'
    v1 = v1[1..-1]
  end
  if v1.nil?
    return false
  elsif v1.empty?
    return false
  elsif v1.match(/[^\d.]/) || v2.match(/[^\d.]/)
    logger.error {"doctemplate_version string includes nondigit chars: v1: \"#{v1}\", v2\"#{v2}\""}
    return false
  elsif v1 == v2
    return true
  else
    v1long = v1.split('.').length
    v2long = v2.split('.').length
    maxlength = v1long > v2long ? v1long : v2long
    0.upto(maxlength-1) { |n|
      # puts "n is #{n}"  ## < debug
      v1split = v1.split('.')[n].to_i
      v2split = v2.split('.')[n].to_i
      if v1split > v2split
        return true
      elsif v1split < v2split
        return false
      elsif n == maxlength-1 && v1split == v2split
        return true
      end
    }
  end
end

#--------------------- RUN
logger.info "############################################################################"
logger.info {"file \"#{Val::Doc.filename_split}\" was dropped into the #{Val::Paths.project_name} folder"}

FileUtils.mkdir_p Val::Paths.tmp_dir  #make the tmpdir

# capture runtype in status_json:
status_hash['runtype'] = Val::Doc.runtype

#try to get submitter info (Dropbox document 'modifier' via api)
if Val::Doc.runtype != 'dropbox'
  user_email = Val::Doc.user_email
  user_name = Val::Doc.user_name
  logger.info {"(looks like this is a 'direct' run, submitter received via flask_api)"}
else
  user_email, user_name = Vldtr::Tools.dropbox_api_call
end

# set_submitter_info in contacts_hash
set_submitter_info(logger,user_email,user_name,contacts_hash,status_hash)

# ATTN: need to add a generic mailtxt for standalone validator
#send email upon file receipt, different mails depending on whether drpobox api succeeded:
if status_hash['api_ok'] && user_email =~ /@/
  body = Val::Resources.mailtext_gsubs(file_recd_txt,'','')
  message = Vldtr::Mailtexts.generic(user_name,user_email,body)
  if File.file?(Val::Paths.testing_value_file)
    message += "\n\nThis message sent from STAGING SERVER"
  end
  Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
else
  Vldtr::Tools.sendmail(Vldtr::Mailtexts.apifail(user_email),'workflows@macmillan.com','')
end


#test fileext for =~ .doc(x)
if Val::Doc.extension !~ /\.doc($|x$)/i
  nondoc(logger,status_hash)  #this is not renamed, and not moved until validator_cleanup
else
  # move and rename IN/inputfile to tmp/working_file
  movedoc(logger)

  # get & log the document custom property values
  doctemplate_version = Vldtr::Tools.runpython(get_custom_doc_prop_py, "#{Val::Files.working_file} #{version_doc_property_name}").strip
  status_hash['doctemplate_version'] = doctemplate_version
  status_hash['bypass_validate'] = Vldtr::Tools.runpython(get_custom_doc_prop_py, "#{Val::Files.working_file} #{bypass_validate_doc_property_name}").to_s.strip

  # determine & log documenttemplatetype.
  #   Most of this (& versioncompare function) lifted directly from bookmaker_addons, with updated messaging
  rsuite_versioncompare = versionCompare(doctemplate_version, rsuite_template_version, logger)
  if rsuite_versioncompare == true
    doctemplatetype = "rsuite"
  else
    sectionstart_versioncompare = versionCompare(doctemplate_version, sectionstart_template_version, logger)
    if sectionstart_versioncompare == true
      doctemplatetype = "sectionstart"
    else
      doctemplatetype = "pre-sectionstart"
    end
  end
  status_hash['doctemplatetype'] = doctemplatetype
  logger.info {"doctemplate_version is \"#{doctemplate_version}\", doctemplatetype: \"#{doctemplatetype}\""}

  # run the python version of isbncheck
  logger.info {"running isbnsearch/password_check python tool"}
  logfile_for_py = File.join(Val::Logs.logfolder, Val::Logs.logfilename)
  py_output = Vldtr::Tools.runpython(isbncheck_py_path, "#{Val::Files.working_file} \"#{logfile_for_py}\" #{doctemplatetype}")

  ## capture any random output from the runpython function call
  logger.info {"output from \"#{isbncheck_py}\": #{py_output}"}
  if Val::Hashes.isbn_hash.has_key?('password_protected')
    status_hash['password_protected'] = Val::Hashes.isbn_hash['password_protected']
  end

  # capture and handle unexpected values
  if !status_hash['password_protected'].empty?
      logger.info {"document is password protected! Skipping alert here, error message will get logged from validator_isbncheck.py"}
      # rm'd the protection alert to JSON here, it's already piped out from isbn_check.py
      # pulled this from mailer in case its needed
  		status_hash['status'] = 'protected .doc(x)'
  elsif Val::Hashes.isbn_hash['completed'] == false
      logger.info {"isbn_check_py error!"}
      # log alert to alerts JSON (for now, continuing to log as 'validator error')
      Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", Val::Hashes.alertmessages_hash["errors"]["validator_error"]["message"].gsub(/PROJECT/,Val::Paths.project_name))
  end
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
