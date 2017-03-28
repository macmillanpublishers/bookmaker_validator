require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
@logger = Val::Logs.logger

htmlmakerjs_path = File.join(Val::Paths.scripts_dir, '..', 'htmlmaker_js')

htmlmaker = File.join(htmlmakerjs_path, 'bin', 'htmlmaker')

styles_json = File.join(htmlmakerjs_path, 'styles.json')

stylefunctions_js = File.join(htmlmakerjs_path, 'style-functions.js')

status_hash = Val::Hashes.status_hash

status_hash['html_conversion'] = ''


# ---------------------- METHOD
## wrapping Bkmkr::Tools.runnode in a new method for this script
def localRunNode(jsfile, args, status_hash)
  	Bkmkr::Tools.runnode(jsfile, args)
rescue => e
  p e
  @logger.info {"error occurred while running #{__method__.to_s}/#{jsfile}: #{e}"}
end


#--------------------- RUN
#convert to html and run content conversions only if the validator finished successfully
if Val::Hashes.status_hash['bookmaker_ready'] == true

  # convert .docx to html
  @logger.info {"this file is bookmaker_ready, running htmlmaker"}
  localRunNode(htmlmaker, "#{Val::Files.working_file} #{Val::Paths.tmp_dir} #{styles_json} #{stylefunctions_js}", status_hash)

  # test if file was created, updated lofs and status hash
  if File.exist?(Val::Files.html_output)
    status_hash['html_conversion'] = true
    @logger.info {"successfully created #{Val::Doc.basename_normalized}.html from our .docx"}

    # make a copy of converted html prior to next transformation (for troubleshooting)
    Mcmlln::Tools.copyFile(Val::Files.html_output, File.join(Val::Paths.tmp_dir, "#{Val::Doc.basename_normalized}_converted_backup.html"))
  else
    status_hash['html_conversion'] = 'false'
    @logger.info {"htmlmaker failed, no html file was produced"}
  end

else
  @logger.info {"Skipping html conversions: according to output from \"validator_checker.rb\", this .docx is not bookmaker ready."}
end

#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
