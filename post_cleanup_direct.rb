require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

done_dir = File.join(Val::Paths.tmp_dir, 'done')
epub_found = true
epub, epub_firstpass = '', ''
post_urls_json = File.join(Val::Paths.bookmaker_scripts_dir, "bookmaker_authkeys", "camelPOST_urls.json")
api_POST_to_camel_py = File.join(Val::Paths.bookmaker_scripts_dir, "bookmaker_connectors", "api_POST_to_camel.py")


#--------------------- LOCAL FUNCTIONS
# this function identical to one in bookmaker-direct_return, except no 'bookmaker_project' param here
def getPOSTurl(url_productstring, post_urls_hash, testing_value_file, relative_destpath)
  # get url
  post_url = post_urls_hash[url_productstring]
  if File.file?(testing_value_file)
    post_url = post_urls_hash["#{url_productstring}_stg"]
  end
  # add dest_folder
  post_url += "?folder=#{relative_destpath}"
  return post_url
rescue => e
  p e
end

# this function identical to one in bookmaker-direct_return; except for .py invocation line
def sendFilesToDrive(files_to_send_list, api_POST_to_camel_py, post_url)
  #loop through files to upload:
  api_result_errs = ''
  for file in files_to_send_list
    argstring = "#{file} #{post_url}"
    api_result = Vldtr::Tools.runpython(api_POST_to_camel_py, argstring)
    if api_result.downcase.strip != 'success'
      api_result_errs += "- api_err: \'#{api_result}\', file: \'#{file}\'\n"
    end
  end
  if api_result_errs == ''
    api_POST_results = 'success'
  else
    api_POST_results = api_result_errs
  end
  return api_POST_results
rescue => e
  p e
  return "error with 'sendFilesToDrive': #{e}"
end



#--------------------- RUN
#find our epubs
if Dir.exist?(done_dir)
  Find.find(done_dir) { |file|
    if file =~ /_EPUBfirstpass.epub$/
      epub_firstpass = file
    elsif file !~ /_EPUBfirstpass.epub$/ && file =~ /_EPUB.epub$/
      epub = file
    end
  }
end

# collect key items from statusfile, or create in its absence
if File.file?(Val::Files.status_file)
  status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
  errors = status_hash['errors']
  index = status_hash['val_report_index'].to_s
else
  errstring = 'status.json missing or unavailable'
  errors = [errstring]
  index = nil
  Vldtr::Tools.log_alert_to_json(Val::Files.alerts_json, "error", errstring)
end
# collect files to send
files_to_send_list = []
#presumes epub is named properly, moves a copy to coresource (if not on staging server)
if File.file?(epub_firstpass)
  files_to_send_list.push(epub_firstpass)
else
  epub_found = false
  if File.file?(epub)
    logger.info {"skipped preparing epub send to outfolder, b/c not named '_firstpass'. Related alertfile should be posted."}
  else
    logger.info {"no epub file found to prepare for send"}
  end
end
if File.file?(Val::Files.stylereport_txt)
  files_to_send_list.push(Val::Files.stylereport_txt)
end
#deal with errors & warnings!
if !Val::Hashes.readjson(Val::Files.alerts_json).empty?
  logger.info {"alerts found, writing warn_notice"}
  alertfile = Vldtr::Tools.write_alerts_to_txtfile(Val::Files.alerts_json, done_dir)
  files_to_send_list.push(alertfile)
end

# send files to Drive!
post_url_productstring = 'egalleymaker'
post_urls_hash = Mcmlln::Tools.readjson(post_urls_json)
post_url = getPOSTurl(post_url_productstring, post_urls_hash, Val::Paths.testing_value_file, File.basename(Val::Paths.tmp_dir))
api_POST_results = sendFilesToDrive(files_to_send_list, api_POST_to_camel_py, post_url)
if api_POST_results == 'success'
  logger.info {"api POST alertfile to Drive successful"}
else
  logger.error {"api_post error(s): #{api_POST_results}"}
  # and escalate:

end

#update Val::Logs.permalog
if File.file?(Val::Logs.permalog)
  permalog_hash = Mcmlln::Tools.readjson(Val::Logs.permalog)
  if index.nil?
    index = permalog_hash.length.to_s
  end
  permalog_hash[index]['epub_found'] = epub_found
  if epub_found && errors.empty?
    permalog_hash[index]['status'] = 'In-house egalley'
  else
    permalog_hash[index]['status'] = 'bookmaker error'
  end
  #write to json Val::Logs.permalog!
    Vldtr::Tools.write_json(permalog_hash,Val::Logs.permalog)
end


#cleanup
if Dir.exists?(Val::Paths.tmp_dir)  then FileUtils.rm_rf Val::Paths.tmp_dir end
if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
