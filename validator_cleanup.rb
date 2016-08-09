require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DEFINITIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
logfile = "#{Val::Logs.logfolder}/#{Val::Logs.logfilename}"

outfolder = File.join(Val::Paths.project_dir, 'OUT', Val::Doc.basename_normalized)
err_notice = File.join(outfolder,"ERROR--#{Val::Doc.filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outfolder,"WARNING--#{Val::Doc.filename_normalized}--validator_completed_with_warnings.txt")
alerts_file = File.join(Val::Paths.mailer_dir,'warning-error_text.json')
alert_hash = Mcmlln::Tools.readjson(alerts_file)

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
	permalog_hash[index]['submitter'] = contacts_hash['submitter_name']
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
if File.file?(Val::Files.stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(Val::Files.stylecheck_file)
	permalog_hash[index]['styled?'] = stylecheck_hash['styled']
	permalog_hash[index]['validator_completed?'] = stylecheck_hash['completed']
end
#write to json Val::Logs.permalog!
Vldtr::Tools.write_json(permalog_hash,Val::Logs.permalog)


#get ready for bookmaker to run on good docs!
if status_hash['bookmaker_ready']
	#change file & folder name to isbn if its available,keep a DONE file with orig filename
	if !isbn.empty?
		#rename Val::Paths.tmp_dir so it doesn't get re-used and has index #s
		tmp_dir_new = File.join(Val::Paths.working_dir,"#{isbn}_to_bookmaker_#{index}")
		Mcmlln::Tools.moveFile(Val::Paths.tmp_dir, tmp_dir_new)
		#update path for working_file
		working_file_updated = File.join(tmp_dir_new, Val::Doc.filename_normalized)
		#make a copy of working file and give it a DONE in filename for troubleshooting from this folder
		#setting up name for done_file: this needs to include working isbn, DONE, and index.  Here we go:
		if Val::Doc.filename_normalized =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    		isbn_condensed = Val::Doc.filename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    		if isbn_condensed != isbn
    			done_file = working_file_updated.gsub(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/,isbn)
    			logger.info {"filename isbn is != lookup isbn, editing filename (for done_file)"}
				else
					done_file = working_file_updated
    		end
  	else
    		logger.info {"adding isbn to done_filename because it was missing"}
			  done_file = working_file_updated.gsub(/#{Val::Doc.extension}$/,"_#{isbn}#{Val::Doc.extension}")
  	end
  	done_file = done_file.gsub(/#{Val::Doc.extension}$/,"_DONE_#{index}#{Val::Doc.extension}")
		Mcmlln::Tools.copyFile(working_file_updated, done_file)
    Mcmlln::Tools.copyFile(done_file, bookmaker_bot_IN)
		#rename working file to keep it distinct from infile
		new_workingfile = working_file_updated.gsub(/#{Val::Doc.extension}$/,"_workingfile#{Val::Doc.extension}")
		File.rename(working_file_updated, new_workingfile)
		#make a copy of infile so we have a reference to it for posts
	  Mcmlln::Tools.copyFile(Val::Doc.input_file, tmp_dir_new)
	else
		logger.info {"for some reason, isbn is empty, can't do renames & moves :("}
	end
else	#if not bookmaker_ready, clean up
	#create outfolder:
	FileUtils.mkdir_p outfolder

	# #if notices exist, collect and bundle them into warnings
	# notices = "NOTICES:\n"
	# if status_hash['epub_format'] == false
	# 	fixlayout_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='fixed_layout' then fixlayout_msg=h['message'] end}}
	# 	notices = "#{notices}- #{fixlayout_msg}\n"
	# end
	# if status_hash['msword_copyedit'] == false
	# 	paprcopyedit_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='paper_copyedit' then paprcopyedit_msg=h['message'] end}}
	# 	notices = "#{notices}- #{paprcopyedit_msg}\n"
	# end
	# if !status_hash['document_styled']
	# 	unstyled_msg=''; alert_hash['notices'].each {|h| h.each {|k,v| if v=='unstyled' then unstyled_msg=h['message'] end}}
	# 	notices = "#{notices}- #{unstyled_msg}\n"
	# end
	# if notices != "NOTICES:\n"
	# 	new_warnings = "#{notices}#{status_hash['warnings']}"
	# 	status_hash['warnings'] = new_warnings
	# end

	#deal with errors & warnings!
	if !status_hash['errors'].empty?
		#errors found!  use the text from mailer to write file:
		text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
		Mcmlln::Tools.overwriteFile(err_notice, text)
		#save the Val::Paths.tmp_dir for review
		if Dir.exists?(Val::Paths.tmp_dir)
			FileUtils.cp_r Val::Paths.tmp_dir, "#{Val::Paths.tmp_dir}__#{timestamp}"  #rename folder
			FileUtils.cp_r "#{Val::Paths.tmp_dir}__#{timestamp}", Val::Logs.logfolder
			logger.info {"errors found, writing err_notice, saving Val::Paths.tmp_dir to logfolder"}
		else
			logger.info {"no tmpdir exists, this was probably not a .doc file"}
		end
	end
	if !status_hash['warnings'].empty? && status_hash['errors'].empty? && !status_hash['bookmaker_ready']
		#warnings found!  use the text from mailer to write file:
		text = status_hash['warnings']
		Mcmlln::Tools.overwriteFile(warn_notice, text)
		logger.info {"warnings found, writing warn_notice"}
	end

	#let's move the original to outbox!
	Mcmlln::Tools.moveFile(Val::Doc.input_file, outfolder)
	logger.info {"moved the original doc to outfolder, now cleaning up!"}
	#and delete tmp files
	if Dir.exists?(Val::Paths.tmp_dir)	then FileUtils.rm_rf Val::Paths.tmp_dir end
	if File.file?(Val::Files.errFile) then FileUtils.rm Val::Files.errFile end
	if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
end
