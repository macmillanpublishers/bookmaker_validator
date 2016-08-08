require 'fileutils'
require 'dropbox_sdk'
require 'open3'
require 'nokogiri'

require_relative '../utilities/oraclequery.rb'
require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger

dropbox_filepath = File.join('/', Val::Paths.project_name, 'IN', Val::Doc.filename_split)
generated_access_token = File.read(File.join(Val::Resources.authkeys_repo,'access_token.txt'))
macro_name = "Validator.IsbnSearch"
file_recd_txt = File.read(File.join(Val::Paths.mailer_dir,'file_received.txt'))
logfile_for_macro = File.join(Val::Logs.logfolder, Val::Logs.logfilename)

root_metadata = ''
contacts_hash = {}
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
status_hash['docisbn_string'] = ''

#--------------------- RUN
logger.info "############################################################################"
logger.info {"file \"#{Val::Doc.filename_normalized}\" was dropped into the #{Val::Paths.project_name} folder"}

FileUtils.mkdir_p Val::Paths.tmp_dir  #make the tmpdir

#try to get submitter info (Dropbox document 'modifier' via api)
begin
	client = DropboxClient.new(generated_access_token)
	root_metadata = client.metadata(dropbox_filepath)
	user_email = root_metadata["modifier"]["email"]
	user_name = root_metadata["modifier"]["display_name"]
rescue Exception => e
	p e   #puts e.inspect
end
if root_metadata.nil? or root_metadata.empty? or !root_metadata or root_metadata['modifier'].nil? or root_metadata['modifier'].empty? or !root_metadata['modifier']
    status_hash['api_ok'] = false
    contacts_hash.merge!(submitter_name: 'Workflows')
    contacts_hash.merge!(submitter_email: 'workflows@macmillan.com')
    logger.info('validator_mailer') {"dropbox api may have failed, not finding file metadata"}
else
    #writing user info from Dropbox API to json
    contacts_hash.merge!(submitter_name: user_name)
    contacts_hash.merge!(submitter_email: user_email)
    Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
    logger.info('validator_mailer') {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", wrote to contacts.json"}
end


#send email upon file receipt, different mails depending on whether drpobox api succeeded:
if status_hash['api_ok'] && user_email =~ /@/
    body = Val::Resources.mailtext_gsubs(file_recd_txt,'','','')

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
CC: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END

	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	end
else

message_b = <<MESSAGE_B_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ERROR: dropbox api lookup failure

Dropbox api lookup failed for file: #{Val::Doc.filename_split}. (found email address: \"#{user_email}\")
MESSAGE_B_END

	unless File.file?(Val::Paths.testing_value_file)
		Vldtr::Tools.sendmail(message_b,'workflows@macmillan.com','')
	end
end


#test fileext for =~ .doc
if Val::Doc.extension !~ /.doc($|x$)/
    status_hash['docfile'] = false
    logger.info {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
    File.open(Val::Files.errFile, 'w') { |f|
        f.puts "Unable to process \"#{Val::Doc.filename_normalized}\". Your document is not a .doc or .docx file."
    }
else
    #if its a .doc(x) lets go ahead and make a working copy
    Mcmlln::Tools.copyFile(Val::Doc.input_file, Val::Files.working_file)

    #get isbns from Manuscript via macro
    Open3.popen2e("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro} \'#{Val::Doc.input_file}\' \'#{macro_name}\' \'#{logfile_for_macro}\'\"") do |stdin, stdouterr, wait_thr|
        stdin.close
        stdouterr.each { |line|
            status_hash['docisbn_string'] << line
        }
    end
    logger.info {"pulled isbnstring from manuscript & added to status.json: #{status_hash['docisbn_string']}"}
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
