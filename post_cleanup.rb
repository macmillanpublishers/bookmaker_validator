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
	et_project_dir = File.join(Val::Paths.server_dropfolder_path,'egalleymaker_stg')
else
	et_project_dir = File.join(Val::Paths.server_dropfolder_path,'egalleymaker')
end
### COMMENTING: the copying to coresourcesend is all handled through bookmaker_connectors repo now.
# if File.file?(Val::Paths.testing_value_file) || Val::Resources.testing == true || Val::Resources.pilot == true
# 	coresource_dir = File.join('S:','validator_tmp','logs','CoreSource-pretend')
# 	FileUtils.mkdir_p coresource_dir
# else
# 	coresource_dir = 'O:'
# end

done_isbn_dir = File.join(Val::Paths.project_dir, 'done', Metadata.pisbn)
outfolder = File.join(et_project_dir,'OUT',Val::Doc.basename_normalized).gsub(/_DONE_#{Val::Posts.index}$/,'')
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

# collect key items from statusfile, or create in its absence
if File.file?(Val::Posts.status_file)
	status_hash = Mcmlln::Tools.readjson(Val::Posts.status_file)
	runtype = status_hash['runtype']
	errors = status_hash['errors']
else
  if Val::Posts.logfolder.downcase.include? "dropbox"
    runtype = 'dropbox'
  else
    runtype = 'direct'
  end
  errstring = 'status.json missing or unavailable'
  errors = [errstring]
  Vldtr::Tools.log_alert_to_json(Val::Posts.alerts_json, "error", errstring)
end

#create outfolder:
Vldtr::Tools.setup_outfolder(outfolder) #replaces the next 8 lines (commenting them out for now)

#presumes epub is named properly, moves a copy to coresource (if not on staging server)
if File.file?(epub_firstpass)
	FileUtils.cp epub_firstpass, outfolder
	logger.info {"copied epub_firstpass to validator outfolder"}
else
  epub_found = false
  if File.file?(epub)
    logger.info {"skipped copying epub to outfolder, b/c not named '_firstpass'. Related alertfile should be posted."}
  else
    logger.info {"no epub file found to copy to outfolder"}
  end
end

#let's move the original to outbox!
logger.info {"moving original file to outfolder.."}
# Mcmlln::Tools.moveFile(validator_infile, outfolder)
Mcmlln::Tools.copyAllFiles(Val::Posts.tmp_original_dir, outfolder)

# move the stylereport.txt to out folder!
logger.info {"moving stylereport.txt file to outfolder... #{File.exists?(Val::Posts.stylereport_txt)}"}
Mcmlln::Tools.moveFile(Val::Posts.stylereport_txt, outfolder)

#deal with errors & warnings!
if !Val::Hashes.readjson(Val::Posts.alerts_json).empty?
	logger.info {"alerts found, writing warn_notice"}
	Vldtr::Tools.write_alerts_to_txtfile(Val::Posts.alerts_json, outfolder)
end

#update Val::Logs.permalog
if File.file?(Val::Posts.permalog)
	permalog_hash = Mcmlln::Tools.readjson(Val::Posts.permalog)
	permalog_hash[Val::Posts.index]['epub_found'] = epub_found
	if epub_found && errors.empty?
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
