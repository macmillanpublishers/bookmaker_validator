require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative '../bookmaker/core/metadata.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup(Val::Posts.logfile_name,Val::Posts.logfolder)
logger = Val::Logs.logger

et_project_dir, coresource_dir  = '', ''		#'et' for egalleymaker :)
if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true
	et_project_dir = File.join(Val::Paths.server_dropbox_path,'egalleymaker_stg')
else
	et_project_dir = File.join(Val::Paths.server_dropbox_path,'egalleymaker')
end
if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true || Val::Resources.pilot == true
	coresource_dir = File.join('S:','validator_tmp','logs','CoreSource-pretend')
	FileUtils.mkdir_p coresource_dir
else
	coresource_dir = 'O:'
end

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
outfolder = File.join(et_project_dir,'OUT',Val::Doc.basename_normalized).gsub(/_DONE_#{Val::Posts.index}$/,'')
warn_notice = File.join(outfolder,"WARNING--#{Val::Doc.filename_normalized}.txt")
err_notice = File.join(outfolder,"ERROR--#{Val::Doc.filename_normalized}.txt")
# validator_infile = File.join(et_project_dir,'IN',Val::Posts.val_infile_name)
errFile = File.join(et_project_dir, "ERROR_RUNNING_#{Val::Posts.val_infile_name}#{Val::Doc.extension}.txt")

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
Vldtr::Tools.setup_outfolder(outfolder) #replaces the next 8 lines (commenting them out for now)

#presumes epub is named properly, moves a copy to coresource (if not on staging server)
if !File.file?(epub) && !File.file?(epub_firstpass)
	epub_found = false
elsif File.file?(epub_firstpass)
	FileUtils.cp epub_firstpass, coresource_dir
	logger.info {"copied epub_firstpass to coresource_dir"}
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
elsif File.file?(epub)
	epub_fp = epub.gsub(/_EPUB.epub$/,'_EPUBfirstpass.epub')
	File.rename(epub, epub_fp)
	FileUtils.cp epub_fp, coresource_dir
	logger.info {"renamed epub to epub_firstpass, copied to coresource_dir"}
	FileUtils.cp epub_fp, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
end

#let's move the original to outbox!
logger.info {"moving original file to outfolder.."}
# Mcmlln::Tools.moveFile(validator_infile, outfolder)
Mcmlln::Tools.copyAllFiles(Val::Posts.tmp_original_dir, outfolder)

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

#update Val::Logs.permalog
if File.file?(Val::Posts.permalog)
	permalog_hash = Mcmlln::Tools.readjson(Val::Posts.permalog)
	permalog_hash[Val::Posts.index]['epub_found'] = epub_found
	if epub_found && status_hash['errors'].empty?
		permalog_hash[Val::Posts.index]['status'] = 'In-house egalley'
	else
		permalog_hash[Val::Posts.index]['status'] = 'bookmaker error'
	end
	#write to json Val::Logs.permalog!
    Vldtr::Tools.write_json(permalog_hash,Val::Posts.permalog)
end


#cleanup
if Dir.exists?(Val::Posts.tmp_dir)	then FileUtils.rm_rf Val::Posts.tmp_dir end
if File.file?(errFile) then FileUtils.rm errFile end
if File.file?(Val::Files.inprogress_file) then FileUtils.rm Val::Files.inprogress_file end
