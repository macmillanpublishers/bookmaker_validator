require 'fileutils'
require 'find'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS

Val::Logs.log_setup()
logger = Val::Logs.logger

status_file = Val::Files.status_file
alerts_json = Val::Files.alerts_json
done_isbn_dir = File.join(Val::Paths.tmp_dir, 'done')

bkmkr_ok = true
epub_firstpass = ''
status_hash = {}
alertstring = ''

#--------------------- FUNCTIONS
def checkForEgalley(done_isbn_dir, alertstring, bkmkr_ok)
  #  find epub file
  epub, epub_firstpass, epub_fp_misnamed = '', '', ''
  Find.find(done_isbn_dir) { |file|
    if file.match(/[\/\\]97[8-9]\d{10}_EPUBfirstpass.epub$/)
      epub_firstpass = file
    elsif file =~ /_EPUBfirstpass.epub$/
      epub_fp_misnamed = file
    elsif file =~ /_EPUB.epub$/
      epub = file
    end
  }
  # log problems
  if epub_firstpass.empty?
    bkmkr_ok = false
    if File.file?(epub_fp_misnamed)
      thiserrstring = "_EPUBfirstpass.epub file created but no ISBN present in epub filename: workflows-team review needed."
    elsif File.file?(epub)
      thiserrstring = "epub created but not named '_firstpass', workflows-team review needed."
    else
      thiserrstring = "no epub found in bookmaker output."
  	end
    alertstring = "#{Val::Hashes.alertmessages_hash['errors']['bookmaker_error']['message'].gsub(/PROJECT/,Val::Paths.project_name)} #{thiserrstring}"
    logger.warn {"#{thiserrstring}"}
  end
  return epub_firstpass, alertstring
rescue => e
  p e
  logger.error {"error during 'checkForEgalley': #{e}"}
  return '', '', false
end

def checkForBookmakerErrs(done_isbn_dir, bkmkr_ok)
  logger.info {"checking for error files in bookmaker..."}
  errtxt_files = []
	Find.find(done_isbn_dir) { |file|
		if file =~ /ERROR.txt/
			logger.info {"error found in done_isbn_dir: #{file}. Adding it as an error for mailer"}
			file = File.basename(file)
			errtxt_files << file
		end
	}
  return errtxt_files, bkmkr_ok
rescue => e
  p e
  logger.error {"error during 'checkForBookmakerErrs': #{e}"}
  return [], false
end

def consolidateBkmkrErrs(errtxt_files, alertstring)
  if !errtxt_files.empty?
    # log bookmaker errors to alerts.json
    alertstring = "#{alertstring}\n#{Val::Hashes.alertmessages_hash['errors']['bookmaker_error']['message'].gsub(/PROJECT/,Val::Paths.project_name)} #{errtxt_files}"
  end
  if !alertstring.empty?
    Vldtr::Tools.log_alert_to_json(alerts_json, "error", alertstring)
    bkmkr_ok = false
  end
  return bkmkr_ok
rescue => e
  p e
  logger.error {"error during 'checkForBookmakerErrs': #{e}"}
  return false
end

#--------------------- MAIN
if Dir.exist?(done_isbn_dir)
  epub_firstpass, alertstring, bkmkr_ok = checkForEgalley(done_isbn_dir, alertstring, bkmkr_ok)
  errtxt_files, bkmkr_ok = checkForBookmakerErrs(done_isbn_dir, bkmkr_ok)
  bkmkr_ok = consolidateBkmkrErrs(errtxt_files, alertstring)
else
  bkmkr_ok = false
  logger.warning {"no done/isbn_dir exists! bookmaker must have an ISBN tied to a different workid! :("}
end

#get info from status.json, define status/errors & status/warnings
if File.file?(status_file)
	status_hash = Mcmlln::Tools.readjson(status_file)
else
	bkmkr_ok = false
	logger.warning {"status.json not present or unavailable, unable to determine what to send"}
end

status_hash['bkmkr_ok'] = bkmkr_ok
status_hash['egalley_file'] = epub_firstpass
Vldtr::Tools.write_json(status_hash, status_file)
