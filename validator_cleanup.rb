require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'



# ---------------------- LOCAL DEFINITIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

outfolder = File.join(Val::Paths.project_dir, 'OUT', Val::Doc.basename_normalized)
err_notice = File.join(outfolder,"ERROR--#{Val::Doc.filename_normalized}--Validator_Failed.txt")
warn_notice = File.join(outfolder,"WARNING--#{Val::Doc.filename_normalized}--validator_completed_with_warnings.txt")
done_file = File.join(Val::Paths.tmp_dir, "#{Val::Doc.basename_normalized}_DONE#{Val::Doc.extension}")
bookmaker_bot_IN = File.join(Val::Paths.bot_egalleys_dir, 'convert')

timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
isbn = ''


#--------------------- RUN
#load info from jsons, start to dish info out to Val::Logs.permalog as available, dump readable json into log
if File.file?(Val::Logs.permalog)
	Val::Logs.permalog_hash = Mcmlln::Tools.readjson(Val::Logs.permalog)
else
	Val::Logs.permalog_hash = {}	
end	

index = Val::Logs.permalog_hash.length + 1
index = index.to_i
Val::Logs.permalog_hash[index]={}
Val::Logs.permalog_hash[index]['file'] = Val::Doc.filename_normalized
Val::Logs.permalog_hash[index]['date'] = timestamp

if File.file?(Val::Files.contacts_file)
	contacts_hash = Mcmlln::Tools.readjson(Val::Files.contacts_file)
	Val::Logs.permalog_hash[index]['submitter'] = contacts_hash['submitter_name']
	#dump json to logfile
	human_contacts = contacts_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}	
	logger.info {"dumping contents of contacts.json:"}
	File.open(logfile, 'a') { |f| f.puts human_contacts }
end	
if File.file?(Val::Files.bookinfo_file)
	bookinfo_hash = Mcmlln::Tools.readjson(Val::Files.bookinfo_file)
	Val::Logs.permalog_hash[index]['isbn'] = bookinfo_hash['isbn']
	Val::Logs.permalog_hash[index]['title'] = bookinfo_hash['title']	
	isbn = bookinfo_hash['isbn']
	#dump json to logfile
	human_bookinfo = bookinfo_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of bookinfo.json:"}
	File.open(logfile, 'a') { |f| f.puts human_bookinfo }
end
if File.file?(Val::Files.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Files.status_file)
	Val::Logs.permalog_hash[index]['errors'] = status_hash['errors']
	Val::Logs.permalog_hash[index]['warnings'] = status_hash['warnings']
	Val::Logs.permalog_hash[index]['bookmaker_ready'] = status_hash['bookmaker_ready']	
	#dump json to logfile
	human_status = status_hash.map{|k,v| "#{k} = #{v}"}
	logger.info {"------------------------------------"}
	logger.info {"dumping contents of status.json:"}
	File.open(logfile, 'a') { |f| f.puts human_status }
else
	status_hash[errors] = "Error occurred, validator failed: no status.json available"
	logger.info {"status.json not present or unavailable, creating error txt"}
end	
if File.file?(Val::Files.stylecheck_file)
	stylecheck_hash = Mcmlln::Tools.readjson(Val::Files.stylecheck_file)
	Val::Logs.permalog_hash[index]['styled?'] = stylecheck_hash['styled']
	Val::Logs.permalog_hash[index]['validator_completed?'] = stylecheck_hash['completed']
end	
#write to json Val::Logs.permalog!
Vldtr::Tools.write_json(Val::Logs.permalog_hash,Val::Logs.permalog)


#deal with errors & warnings!
if !status_hash['errors'].empty?
	#create outfolder:
	FileUtils.mkdir_p outfolder
	#errors found!  use the text from mailer to write file:
	text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
	Mcmlln::Tools.overwriteFile(err_notice, text)
	#save the Val::Paths.tmp_dir for review
	if Dir.exists?(Val::Paths.tmp_dir)
		FileUtils.cp_r Val::Paths.tmp_dir, "#{Val::Paths.tmp_dir}__#{timestamp}"  #rename folder
		FileUtils.mv "#{Val::Paths.tmp_dir}__#{timestamp}", logfolder 	
		logger.info {"errors found, writing err_notice, saving Val::Paths.tmp_dir to logfolder"}
	else
		logger.info {"no tmpdir exists, this was probably not a .doc file"}
	end
	#let's move the original to outbox!
	Mcmlln::Tools.moveFile(Val::Doc.input_file, outfolder)
end	
if !status_hash['warnings'].empty? && status_hash['errors'].empty? && !status_hash['bookmaker_ready']
	#create outfolder:
	FileUtils.mkdir_p outfolder
	#warnings found!  use the text from mailer to write file:
	text = status_hash['warnings']
	Mcmlln::Tools.overwriteFile(warn_notice, text)
	logger.info {"warnings found, writing warn_notice"}
end	


#get ready for bookmaker to run on good docs!
if status_hash['bookmaker_ready']
	#change file & folder name to isbn if its available,keep a DONE file with orig filename
	if !isbn.empty?
		#rename Val::Paths.tmp_dir so it doesn't get re-used and has index #
		Val::Paths.tmp_dir_old = Val::Paths.tmp_dir
		Val::Paths.tmp_dir = File.join(Val::Paths.working_dir,"#{isbn}_to_bookmaker-#{index}")
		Mcmlln::Tools.moveFile(Val::Paths.tmp_dir_old, Val::Paths.tmp_dir)
		#make a copy of working file and give it a DONE in filename for troubleshooting from this folder
		Val::Files.working_file = File.join(Val::Paths.tmp_dir, Val::Doc.filename_normalized)
		done_file = Val::Files.working_file
		#setting up name for done_file: this needs to include working isbn, DONE, and index.  Here we go:
		if Val::Files.working_file =~ /9(7(8|9)|-7(8|9)|7-(8|9)|-7-(8|9))[0-9-]{10,14}/
    		isbn_condensed = Val::Files.working_file.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
    		if isbn_condensed != isbn
    			done_file = Val::Files.working_file.gsub(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/,isbn)
    			logger.info {"filename isbn is != lookup isbn, editing filename (for done_file)"}
    		end
    	else	
    		logger.info {"adding isbn to done_filename because it was missing"}
			done_file = Val::Files.working_file.gsub(/#{Val::Doc.extension}$/,"_#{isbn}#{Val::Doc.extension}")
    	end	
    	done_file = done_file.gsub(/#{Val::Doc.extension}$/,"_DONE-#{index}#{Val::Doc.extension}")
    	Mcmlln::Tools.copyFile(Val::Files.working_file, done_file)
	    Mcmlln::Tools.copyFile(done_file, bookmaker_bot_IN)
		#rename working file to keep it distinct from infile
		new_workingfile = Val::Files.working_file.gsub(/#{Val::Doc.extension}$/,"_workingfile#{Val::Doc.extension}")
		File.rename(Val::Files.working_file, new_workingfile)
		#make a copy of infile so we have a reference to it for posts
	    Mcmlln::Tools.copyFile(Val::Doc.input_file, Val::Paths.tmp_dir)		
	else
		logger.info {"for some reason, isbn is empty, can't do renames & moves :("}
	end	
else	#if not bookmaker_ready, clean up
	if Dir.exists?(Val::Paths.tmp_dir)	then FileUtils.rm_rf Val::Paths.tmp_dir end
	if File.file?(Val::Files.errFile) then FileUtils.rm Val::Files.errFile end
	if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end	
end	
