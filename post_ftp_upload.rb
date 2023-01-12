require 'fileutils'
require 'net/sftp'
require 'net/smtp'
require 'find'
require 'logger'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

status_file = Val::Files.status_file
upload_ok = ''

#--------------------- CLASSES
class RSuite
  def self.upload(file, user, pass, host)
    status = false
    Net::SFTP.start(host, user, {:password => pass, :port => 22, :verbose => :debug}) do |sftp|
      sftp.upload!("#{file}")
    end
    status = true
    return status
  rescue Errno::ECONNREFUSED => e
      p e.message
      p e.backtrace
      return status
  end
end

# ------------- METHODS

def sendMessage(message, email)
  Net::SMTP.start(Val::Resources.smtp_address) do |smtp|
    smtp.send_message message, email,
                               email
  end
end

# ------------- MAIN
# get file and status
status_hash = Mcmlln::Tools.readjson(status_file)
rsfile = status_hash['egalley_file']

if !rsfile.empty? && status_hash['bkmkr_ok'] === true
  # get creds
  rs_ftp_creds_hash = Mcmlln::Tools.readjson(Val::Resources.rs_ftp_creds_json)
  rsuser = rs_ftp_creds_hash['rsuser']
  rspass = rs_ftp_creds_hash['rspass']
  rshost = rs_ftp_creds_hash['rshost']
  rshost_stg = rs_ftp_creds_hash['rshost_stg']

  # upload
  if File.file?(testing_value_file)
    server_shortname = "RSuite-Staging sFTP"
    status = RSuite.upload(rsfile, rsuser, rspass, rshost_stg)
    email_disclaimer = "\nNOTE: this message sent from Bkmkr-STAGING server\n"
  else
    server_shortname = "RSuite-PROD sFTP"
    status = RSuite.upload(rsfile, rsuser, rspass, rshost)
    email_disclaimer = ""
  end

  # log success or failure
  if status == true
    transfer = "Uploaded #{filename} to #{server_shortname} (egalley dir)"
    message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: SUCCESS: Loaded #{filename} to the #{server_shortname} (egalley dir)

The upload was successful.
#{email_disclaimer}
MESSAGE_END
    logger.info(transfer)
    upload_ok = true
  else
    transfer = "Attempted to load #{filename} to #{server_shortname} (egalley dir), but was unable to."
    message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: FAIL: Could not upload #{filename} to the #{server_shortname} (egalley dir)

The upload attempt failed.
#{email_disclaimer}
MESSAGE_END
    logger.error(transfer)
    upload_ok = false
  end

  sendMessage(message, 'workflows@macmillan.com')
  logger.info("sent transfer notification to workflows")
else
  logger.warn("")
end

status_hash['upload_ok'] = upload_ok
Vldtr::Tools.write_json(status_hash, status_file)
