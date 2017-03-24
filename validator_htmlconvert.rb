require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

htmlmakerjs_path = File.join(Val::Paths.scripts_dir, 'htmlmaker_js')

htmlmaker = File.join(htmlmakerjs_path, 'bin', 'htmlmaker')

styles_json = File.join(htmlmakerjs_path, 'styles.json')

stylefunctions_js = File.join(htmlmakerjs_path, 'style-functions.js')

htmltohtmlbook_js = File.join(htmlmakerjs_path, 'lib', 'htmltohtmlbook.js')

generateTOC_js = File.join(htmlmakerjs_path, 'lib', 'generateTOC.js')

html_output = File.join(Val::Paths.tmp_dir, "#{Val::Doc.basename_normalized}.html")

status_hash = Val::Hashes.status_hash

status_hash['html_conversions'] = ''

# ---------------------- METHOD
def convertToHTML(htmlmaker, docpath, outputdir, styles_json, stylefunctions_js, status_hash)
  `"#{htmlmaker} #{docpath} #{outputdir} #{styles_json} #{stylefunctions_js}"`
  status_hash['html_conversions'] = true
rescue => e
  status_hash['html_conversions'] = false
  p e
  logger.info {"error occurred while converting .docx to html (#{__method__.to_s}): #{e}"}
end

## wrapping Vldtr::Tools.runnode in a new method for this script; for easy logger and verifying infile exists
def localRunNode(jsfile, html, status_hash)
  if File.exist?(html)
  	Vldtr::Tools.runnode(jsfile, args)
  else
    logger.info {"file: \"#{Val::Doc.basename_normalized}.html\" is not present; skipping #{__method__.to_s}"}
  end
rescue => e
  status_hash['html_conversions'] = false
  p e
  logger.info {"error occurred while running #{__method__.to_s}: #{e}"}
end


#--------------------- RUN
#convert to html and run content conversions only if the validator finished successfully
if Val::Hashes.status_hash['bookmaker_ready'] == true

  # convert .docx to html
  convertToHTML(htmlmaker, Val::Files.working_file, Val::Paths.tmp_dir, styles_json, stylefunctions_js, status_hash)

  # make a copy of converted html prior to next transformation (for troubleshooting)
  Mcmlln::Tools.copyFile(html_output, File.join(Val::Paths.tmp_dir, "#{Val::Doc.basename_normalized}_converted_backup.html"))

  # run html to htmlboook js conversion
  if status_hash['html_conversions'] == true
    localRunNode(htmltohtmlbook_js, html_output, status_hash)

    # make a copy of htmlbook html prior to next conversion (for troubleshooting)
    Mcmlln::Tools.copyFile(html_output, File.join(Val::Paths.tmp_dir, "#{Val::Doc.basename_normalized}_htmlbookjs_backup.html"))
  end

  # generate a toc for the htmlbook html via js
  if status_hash['html_conversions'] == true
    localRunNode(generateTOC_js, html_output, status_hash)
  end

  # make sure html file is present
  if !File.exist?(html_output)
    status_hash['html_conversions'] = false
  end

else
  logger.info {"Skipping html conversions: according to output from \"validator_checker.rb\", this .docx is not bookmaker ready."}
end


#update status file with new news!
Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
