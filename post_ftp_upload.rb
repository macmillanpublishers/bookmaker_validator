require 'fileutils'
require 'net/sftp'
require 'net/smtp'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
@logger = Val::Logs.logger

status_file = Val::Files.status_file
upload_ok = ''

#--------------------- CLASSES
class RSuite
  def self.upload(file, user, pass, host)
    @logger.info("uploading file #{File.basename(file)}to #{host}")
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
  @logger.info("sending ftp status email")
  Net::SMTP.start(Val::Resources.smtp_address) do |smtp|
    smtp.send_message message, email,
                               email
  end
rescue => e
  p e
  @logger.error("error sending email: #{e}")
end

# ------------- MAIN
# get file and status
status_hash = Mcmlln::Tools.readjson(status_file)
rsfile = status_hash['egalley_file']
filename = File.basename(rsfile)

if !rsfile.empty? && status_hash['bkmkr_ok'] == true
  # get creds
  rs_ftp_creds_hash = Mcmlln::Tools.readjson(Val::Resources.rs_ftp_creds_json)
  rsuser = rs_ftp_creds_hash['rsuser']
  rspass = rs_ftp_creds_hash['rspass']
  rshost = rs_ftp_creds_hash['rshost']
  rshost_stg = rs_ftp_creds_hash['rshost_stg']

  # upload
  if File.file?(Val::Paths.testing_value_file)
    server_shortname = "RSuite-Staging sFTP"
    status = RSuite.upload(rsfile, rsuser, rspass, rshost_stg)
    email_disclaimer = "\nNOTE: this message sent from Bkmkr-STAGING server\n"
  else
    server_shortname = "RSuite-PROD sFTP"
    status = RSuite.upload(rsfile, rsuser, rspass, rshost)
    email_disclaimer = ""
  end

  # log success or failure, set email msg
  if status == true
    transfer_msg = "Uploaded #{filename} to #{server_shortname} (egalley dir)"
    message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: SUCCESS: #{transfer_msg}

The upload was successful.
#{email_disclaimer}
MESSAGE_END
    @logger.info(transfer_msg)
    upload_ok = true
  else
    transfer_msg = "Could not upload #{filename} to the #{server_shortname} (egalley dir)"
    message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: FAIL: #{transfer_msg}

The upload attempt failed.
#{email_disclaimer}
MESSAGE_END
    @logger.error(transfer_msg)
    upload_ok = false
  end

  sendMessage(message, 'workflows@macmillan.com')

elsif rsfile.empty?
  @logger.warn("no egalley file, skipping ftp upload")
elsif status_hash['bkmkr_ok'] != true
  @logger.warn("bookmaker or status-check error encountered, skipping ftp upload")
end

status_hash['upload_ok'] = upload_ok
Vldtr::Tools.write_json(status_hash, status_file)
