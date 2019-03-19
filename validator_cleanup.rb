require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DEFINITIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
logfile = "#{Val::Logs.logfolder}/#{Val::Logs.logfilename}"

outfolder = File.join(Val::Paths.project_dir, 'OUT', Val::Doc.basename_normalized)

bookmaker_bot_IN = ''
if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true
	bookmaker_bot_IN = File.join(Val::Paths.server_dropbox_path,'bookmaker_bot_stg','bookmaker_egalley','convert')
else
	bookmaker_bot_IN = File.join(Val::Paths.server_dropbox_path,'bookmaker_bot','bookmaker_egalley','convert')
end
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
isbn = ''
done_file = ''



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
	permalog_hash[index]['errors'] = status_hash['errors']
	permalog_hash[index]['warnings'] = status_hash['warnings']
	permalog_hash[index]['bookmaker_ready'] = status_hash['bookmaker_ready']
	permalog_hash[index]['status'] = status_hash['status']
	permalog_hash[index]['styled?'] = status_hash['document_styled']
	permalog_hash[index]['validator_completed?'] = status_hash['validator_py_complete']
  permalog_hash[index]['doctemplatetype'] = status_hash['doctemplatetype']
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
if status_hash['bookmaker_ready'] && Val::Paths.project_name =~ /egalleymaker/
	#change file & folder name to isbn if its available,keep a DONE file with orig filename
	if !isbn.empty?
		#rename Val::Paths.tmp_dir so it doesn't get re-used and has index #s
		tmp_dir_new = File.join(Val::Paths.working_dir,"#{isbn}_to_bookmaker_#{index}")
		Mcmlln::Tools.moveFile(Val::Paths.tmp_dir, tmp_dir_new)
    #update path for converted_file / working_file
    if status_hash['doctemplatetype'] == 'sectionstart'
		  converted_file_updated = File.join(tmp_dir_new, Val::Doc.converted_docx_filename)
    elsif status_hash['doctemplatetype'] == 'rsuite'
      converted_file_updated= File.join(tmp_dir_new, Val::Doc.filename_docx)
		else status_hash['doctemplatetype'] == 'pre-sectionstart'
      converted_file_updated= File.join(tmp_dir_new, Val::Doc.filename_docx)
    end
    #make a copy of working file and give it a DONE in filename for troubleshooting from this folder
		#setting up name for done_file: this needs to include working isbn, DONE, and index.  Here we go:
		if Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
			isbn_condensed = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
			if isbn_condensed != isbn
				done_file = converted_file_updated.gsub(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/,isbn)
				logger.info {"filename isbn is != lookup isbn, editing filename (for done_file)"}
			else
				done_file = converted_file_updated
			end
		else
			logger.info {"adding isbn to done_filename because it was missing"}
			# converted_file_updated features '_converted' suffix for section-start, new regex looks for either
			done_file = converted_file_updated.gsub(/((_converted)*.docx)$/,"_#{isbn}\\1")
		end
		# same as above: converted_file_updated features '_converted' suffix for section-start, new regex looks for either
		done_file = done_file.gsub(/(_converted)*.docx$/,"_DONE_#{index}.docx")
		logger.info("checking renaming: converted file exist? #{File.exists?(converted_file_updated)}")
    logger.info {"cp 3: converted_file_updated is \"#{converted_file_updated}\",done_file is \"#{done_file}\""}
		Mcmlln::Tools.copyFile(converted_file_updated, done_file)
		logger.info("checking rename 2: done file exist? #{File.exists?(done_file)}")
		Mcmlln::Tools.copyFile(done_file, bookmaker_bot_IN)
		#make a copy of infile so we have a reference to it for posts
		Mcmlln::Tools.copyFile(Val::Files.original_file, tmp_dir_new)
	else
		logger.info {"for some reason, isbn is empty, can't do renames & moves :("}
	end
else	#if not bookmaker_ready, clean up

	#create outfolder:
	Vldtr::Tools.setup_outfolder(outfolder)

	#save the Val::Paths.tmp_dir for review if error occurred
	if !status_hash['errors'].empty?
		if Dir.exists?(Val::Paths.tmp_dir) && status_hash['docfile'] == true
			FileUtils.cp_r Val::Paths.tmp_dir, "#{Val::Paths.tmp_dir}__#{timestamp}"  #rename folder
			FileUtils.cp_r "#{Val::Paths.tmp_dir}__#{timestamp}", Val::Logs.logfolder
			logger.info {"errors found, writing err_notice, saving Val::Paths.tmp_dir to logfolder"}
		end
	end

	#write alert text file!
	if !Val::Hashes.alerts_hash.empty?
		Vldtr::Tools.write_alerts_to_txtfile(Val::Files.alerts_json, outfolder)
		logger.info {"warnings found, writing warn_notice"}
	end

	#let's move the original to outbox!
	if File.file?("#{Val::Doc.input_file_untag_chars}") && status_hash['docfile'] == false
		Mcmlln::Tools.moveFile(Val::Doc.input_file_untag_chars, outfolder)
	elsif Val::Paths.project_name =~ /egalleymaker/ && File.file?(Val::Files.original_file)
		Mcmlln::Tools.copyAllFiles(Val::Paths.tmp_original_dir, outfolder)
	elsif File.file?(Val::Files.original_file)
		FileUtils.cp_r(Val::Paths.tmp_original_dir, outfolder)
	else
		logger.info {"unable to move original file to outfolder, it was not present where it should have been"}
	end
	logger.info {"moved the original doc to outfolder, now cleaning up!"}

	# now let's move the stylereport.txt to the out folder! Unless doc was unstyled
	if status_hash['document_styled'] == true
		logger.info {"moving stylereport.txt file to outfolder.."}
		Mcmlln::Tools.moveFile(Val::Files.stylereport_txt, outfolder)
	end

	#and delete tmp files
	if Dir.exists?(Val::Paths.tmp_dir)	then FileUtils.rm_rf Val::Paths.tmp_dir end
	if File.file?(Val::Files.errFile) then FileUtils.rm Val::Files.errFile end
	if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
end
