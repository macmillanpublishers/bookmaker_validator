require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'



# ---------------------- LOCAL DECLARATIONS
Vldtr::Logs.log_setup(Val::Posts.logfile_name)
logger = Vldtr::Logs.logger

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
permalog = File.join(Val::Logs.logfolder,'validator_history_report.json')
permalogtxt = File.join(Val::Logs.logfolder,'validator_history_report.txt')
outfolder = File.join(Val::Posts.et_project_dir,'OUT',Val::Doc.basename_normalized).gsub(/_DONE-#{Val::Posts.index}$/,'')
warn_notice = File.join(outfolder,"WARNING--#{Val::Doc.filename_normalized}--validator_completed_with_warnings.txt")
err_notice = File.join(outfolder,"ERROR--#{Val::Doc.filename_normalized}--Validator_Failed.txt")
validator_infile = File.join(Val::Posts.et_project_dir,'IN',Val::Posts.val_infile_name)
errFile = File.join(Val::Posts.et_project_dir, "ERROR_RUNNING_#{Val::Posts.val_infile_name}#{Val::Doc.extension}.txt")

coresource_dir = 'O:'
epub_found = true
epub, epub_firstpass = '', ''



#--------------------- RUN
#find our epubs
if Dir.exist?(done_isbn_dir)
	Find.find(done_isbn_dir) { |file|
		if file =~ /_EPUBfirstpass.epub$/
			epub_firstpass = file
		elsif file !~ /_EPUBfirstpass.epub$/ && file =~ /_EPUB.epub$/
			epub = file
		end
	}
end

#create outfolder:
FileUtils.mkdir_p outfolder

#presumes epub is named properly, moves a copy to coresource (if not on staging server)
if !File.file?(epub) && !File.file?(epub_firstpass)
	epub_found = false
elsif File.file?(epub_firstpass)
	if !File.file?(Val::AbsolutePaths.testing_value_file)
		FileUtils.cp epub_firstpass, coresource_dir
		logger.info {"copied epub_firstpass to coresource_dir"}
	end
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
elsif File.file?(epub)
	File.rename(epub, epub_firstpass)
	if !File.file?(Val::AbsolutePaths.testing_value_file)
		FileUtils.cp epub_firstpass, coresource_dir
		logger.info {"copied epub_firstpass to coresource_dir"}
	end
	logger.info {"renamed epub to epub_firstpass, copied to coresource_dir"}
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
end

#let's move the original to outbox!
logger.info {"moving original file to outfolder.."}
FileUtils.mv validator_infile, outfolder

#deal with errors & warnings!
if File.file?(Val::Posts.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Posts.status_file)
	if !status_hash['errors'].empty?
		text = "#{status_hash['errors']}\n#{status_hash['warnings']}"
		Mcmlln::Tools.overwriteFile(err_notice, text)
		logger.info {"errors found, writing err_notice"}
	end
	if !status_hash['warnings'].empty? && status_hash['errors'].empty?
		text = status_hash['warnings']
		Mcmlln::Tools.overwriteFile(warn_notice, text)
		logger.info {"warnings found, writing warn_notice"}
	end
else
	logger.info {"status.json not present or unavailable!?"}
end

#update permalog
if File.file?(permalog)
	permalog_hash = Mcmlln::Tools.readjson(permalog)
	permalog_hash[Val::Posts.index]['bookmaker_ran'] = true
	permalog_hash[Val::Posts.index]['epub_found'] = true
	if !epub_found
		permalog_hash[Val::Posts.index]['epub_found'] = false
	end
	#write to json permalog!
    Vldtr::Tools.write_json(permalog_hash,permalog)
end


#cleanup
if Dir.exists?(Val::Posts.tmp_dir)	then FileUtils.rm_rf Val::Posts.tmp_dir end
if File.file?(errFile) then FileUtils.rm errFile end
if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
