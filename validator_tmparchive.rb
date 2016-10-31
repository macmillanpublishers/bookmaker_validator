require 'fileutils'
require 'dropbox_sdk'
require 'open3'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
logger = Val::Logs.logger
macro_name = "Validator.IsbnSearch"
file_recd_txt = File.read(File.join(Val::Paths.mailer_dir,'file_received.txt'))

contacts_hash = {}
contacts_hash['ebooksDept_submitter'] = false
status_hash = {}
status_hash['api_ok'] = true
status_hash['docfile'] = true
user_email = ''

#---------------------  METHODS
def set_submitter_info(logger,user_email,user_name,contacts_hash,status_hash)
	if user_email.nil? or user_email.empty? or !user_email
	    status_hash['api_ok'] = false
	    contacts_hash.merge!(submitter_name: 'Workflows')
	    contacts_hash.merge!(submitter_email: 'workflows@macmillan.com')
	    logger.info {"dropbox api may have failed, not finding file metadata"}
	else
		#check to see if submitter is in ebooks dept.:
		staff_hash = Mcmlln::Tools.readjson(Val::Files.staff_emails)  		#read in our static pe/pm json
		for i in 0..staff_hash.length - 1
				if user_email == "#{staff_hash[i]['email']}"
						if "#{staff_hash[i]['division']}" == 'Ebooks' || "#{staff_hash[i]['division']}" == 'Workflow'
								contacts_hash['ebooksDept_submitter'] = true
								logger.info {"#{user_name} is a member of ebooks or Workflow dept, flagging that to edit user comm. addressees"}
						end
				end
		end
    #writing user info from Dropbox API to json
    contacts_hash.merge!(submitter_name: user_name)
    contacts_hash.merge!(submitter_email: user_email)
    Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
    logger.info {"file submitter retrieved, display name: \"#{user_name}\", email: \"#{user_email}\", wrote to contacts.json"}
	end
end
def nondoc(logger,status_hash)
	status_hash['docfile'] = false
	logger.info {"This is not a .doc or .docx file. Posting error.txt to the project_dir for user."}
	File.open(Val::Files.errFile, 'w') { |f|
			f.puts "Unable to process \"#{Val::Doc.filename_normalized}\". Your document is not a .doc or .docx file."
	}
end
def movedoc(logger)
	#if its a .doc(x) lets go ahead and move it to tmpdir, keep a pristing copy in subfolder
	FileUtils.mkdir_p Val::Paths.tmp_original_dir
	Mcmlln::Tools.moveFile(Val::Doc.input_file_untag_chars, Val::Files.original_file)
	Mcmlln::Tools.copyFile(Val::Files.original_file, Val::Files.working_file)
	if Val::Doc.filename_split == Val::Doc.filename_normalized
		logger.info {"moved #{Val::Doc.filename_split} to tmpdir"}
	else
		logger.info {"renamed \"#{Val::Doc.filename_split}\" to \"#{Val::Doc.filename_normalized}\" and moved to tmpdir "}
	end
end

#--------------------- RUN
logger.info "############################################################################"
logger.info {"file \"#{Val::Doc.filename_split}\" was dropped into the #{Val::Paths.project_name} folder"}

FileUtils.mkdir_p Val::Paths.tmp_dir  #make the tmpdir

#try to get submitter info (Dropbox document 'modifier' via api)
user_email, user_name = Vldtr::Tools.dropbox_api_call

#set_submitter_info in contacts_hash
set_submitter_info(logger,user_email,user_name,contacts_hash,status_hash)

# ATTN: need to add a generic mailtxt for standalone validator
#send email upon file receipt, different mails depending on whether drpobox api succeeded:
unless File.file?(Val::Paths.testing_value_file)
	if status_hash['api_ok'] && user_email =~ /@/
    body = Val::Resources.mailtext_gsubs(file_recd_txt,'','','')
		message = Vldtr::Mailtexts.generic(user_name,user_email,body) #or "#{body}" ?
		Vldtr::Tools.sendmail("#{message}",user_email,'workflows@macmillan.com')
	else
		Vldtr::Tools.sendmail(Vldtr::Mailtexts.apifail(user_email),'workflows@macmillan.com','')
	end
end

#test fileext for =~ .doc
if Val::Doc.extension !~ /.doc($|x$)/
	nondoc(logger,status_hash)  #this is not renamed, and not moved until validator_cleanup
else
	movedoc(logger)
	logger.info {"running isbnsearch/password_check macro"}
	status_hash['docisbn_string'] = Vldtr::Tools.run_macro(logger,macro_name) #run macro
	status_hash['password_protected'] = Val::Hashes.isbn_hash['initialize']['password_protected']
	if Val::Hashes.isbn_hash['completed'] == false then logger.info {"isbnsearch macro error!"} end
	if status_hash['password_protected'] == true then logger.info {"document is password protected!"} end
end

Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
Vldtr::Tools.write_json(contacts_hash,Val::Files.contacts_file)
