require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DEFINITIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
logfile = "#{Val::Logs.logfolder}/#{Val::Logs.logfilename}"

bookmaker_direct_bat = File.join(Val::Paths.bookmaker_scripts_dir, 'bookmaker_deploy', 'automated_EGALLEY_direct.bat')
bkmkr_bat_runtype = 'direct'
bkmkr_bat_arg3 = 'egalley'  # <-- placeholder arg
bkmkr_bat_arg4 = 'placeholder'  # <-- placeholder arg
post_urls_json = File.join(Val::Paths.scripts_dir, "bookmaker_authkeys", "camelPOST_urls.json")
api_POST_to_camel_py = File.join(Val::Paths.scripts_dir, "bookmaker_connectors", "api_POST_to_camel.py")
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
isbn = ''

#--------------------- LOCAL FUNCTIONS

def spawnBookmaker(cmd, args)
  Val::Logs.return_stdOutErr  #stop console log redirect to file
  pid = spawn("#{cmd} #{args}")
  Process.detach(pid)
  Val::Logs.redirect_stdOutErr(Val::Logs.std_logfile)  #turn console log redirect back on
  return pid
rescue => e
  p e
end

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
    api_result = Vlftr::Tools.runpython(api_POST_to_camel_py, argstring)
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
#load info from jsons, start to dish info out to Val::Logs.permalog as available, dump readable json into log
if File.file?(Val::Logs.permalog)
	permalog_hash = Mcmlln::Tools.readjson(Val::Logs.permalog)
else
	permalog_hash = {}
end

index = permalog_hash.length + 1
index = index.to_i
permalog_hash[index]={}
permalog_hash[index]['file'] = Val::Doc.filename_normalized
permalog_hash[index]['date'] = timestamp

if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
	permalog_hash[index]['submitter_name'] = contacts_hash['submitter_name']
	permalog_hash[index]['submitter_email'] = contacts_hash['submitter_email']
	#dump json to logfile
	human_contacts = contacts_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of contacts.json:"}
	File.open(logfile, 'a') { |f| f.puts human_contacts }
end
if File.file?(Val::Files.bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(Val::Files.bookinfo_file)
	permalog_hash[index]['isbn'] = bookinfo_hash['isbn']
	permalog_hash[index]['title'] = bookinfo_hash['title']
	permalog_hash[index]['author'] = bookinfo_hash['author']
	permalog_hash[index]['imprint'] = bookinfo_hash['imprint']
	permalog_hash[index]['product_type'] = bookinfo_hash['product_type']
	isbn = bookinfo_hash['isbn']
	#dump json to logfile
	human_bookinfo = bookinfo_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of bookinfo.json:"}
	File.open(logfile, 'a') { |f| f.puts human_bookinfo }
end
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
  # write index to status_hash for pickup in post.rb scripts
  status_hash['val_report_index'] = index
  Vldtr::Tools.write_json(status_hash,Val::Files.status_file)
  # dump other key status-contents into permalog
	permalog_hash[index]['errors'] = status_hash['errors']
	permalog_hash[index]['warnings'] = status_hash['warnings']
	permalog_hash[index]['bookmaker_ready'] = status_hash['bookmaker_ready']
	permalog_hash[index]['status'] = status_hash['status']
	permalog_hash[index]['styled?'] = status_hash['document_styled']
	permalog_hash[index]['validator_completed?'] = status_hash['validator_py_complete']
  permalog_hash[index]['doctemplatetype'] = status_hash['doctemplatetype']
  permalog_hash[index]['runtype'] = status_hash['runtype']
	#dump json to logfile
	human_status = status_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of status.json:"}
	File.open(logfile, 'a') { |f| f.puts human_status }
else
	status_hash = {}
	status_hash[errors] = "Error occurred, validator failed: no status.json available"
	logger.info {"status.json not present or unavailable, creating error txt"}
end
#write to json Val::Logs.permalog!
Vldtr::Tools.write_json(permalog_hash,Val::Logs.permalog)


#get ready for bookmaker to run on good docs!
if status_hash['bookmaker_ready']
  # setup args, launch our bookmaker_bat directly!
  bkmkr_bat_args = "#{Val::Files.working_file} #{bkmkr_bat_runtype} \"#{bkmkr_bat_arg3}\" \"#{bkmkr_bat_arg4}\""
  logger.info {"we're bookmaker ready, spawning bkmkr_automated_egalley process; args: #{bkmkr_bat_args}"}
  pid = spawnBookmaker(bookmaker_direct_bat, bkmkr_bat_args)
  logger.info {"bkmkr_automated_egalley process started, & detached: pid #{pid}"}

else	#if not bookmaker_ready, clean up

	#save the Val::Paths.tmp_dir for review if error occurred
	if !status_hash['errors'].empty?
		if Dir.exists?(Val::Paths.tmp_dir) && status_hash['docfile'] == true
			FileUtils.cp_r Val::Paths.tmp_dir, "#{Val::Paths.tmp_dir}__#{timestamp}"  #rename folder
			FileUtils.cp_r "#{Val::Paths.tmp_dir}__#{timestamp}", Val::Logs.logfolder
			logger.info {"errors found, saving Val::Paths.tmp_dir to logfolder"}
		end
	end

	#write alert text file!
	if !Val::Hashes.alerts_hash.empty?
		alertfile = Vldtr::Tools.write_alerts_to_txtfile(Val::Files.alerts_json, Val::Paths.tmp_dir)
		logger.info {"alerts found, writing warn_notice"}
	end

  # send text errfile to camel/drive
  post_url_productstring = 'egalleymaker'
  post_urls_hash = Mcmlln::Tools.readjson(post_urls_json)
  post_url = getPOSTurl(post_url_productstring, post_urls_hash, Val::Paths.testing_value_file, File.basename(Val::Paths.tmp_dir))
  api_POST_results = sendFilesToDrive([alertfile], api_POST_to_camel_py, post_url)
  if api_POST_results == 'success'
    logger.info {"api POST errfile to Drive successful"}
  else
    logger.error {"api_post error(s): #{api_POST_results}"}
    # and escalate:

  end

  #### this will / would only be a thing if we get rs_Validate integrated with egallymaker.
  #### Leaving here as a nod to that possibility
	# # now let's move the stylereport.txt to the out folder! Unless doc was unstyled
	# if status_hash['document_styled'] == true
	# 	logger.info {"moving stylereport.txt file to outfolder.."}
	# 	Mcmlln::Tools.moveFile(Val::Files.stylereport_txt, outfolder)
	# end

	#and delete tmp files
	if Dir.exists?(Val::Paths.tmp_dir)	then FileUtils.rm_rf Val::Paths.tmp_dir end
	if File.file?(Val::Files.errFile) then FileUtils.rm Val::Files.errFile end
	if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
end
