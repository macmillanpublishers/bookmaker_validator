require 'dropbox_sdk'
# Install this the SDK with "gem install dropbox-sdk"
require 'json'
require 'net/smtp'
require 'logger'
require 'find'

#for testing on staging:
#remember to update testing_value_file (line 32 / 33)
#remember to update mail to & from back to workflows@macmillan.com (line 120/121)


# ---------------------- VARIABLES
#old vars
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
input_file_normalized = input_file.gsub(/ /, "")
filename_normalized = filename_split.gsub(/ /, "")
basename_normalized = File.basename(filename_normalized, ".*")
extension = File.extname(filename_normalized)
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
#new vars:
dropbox_filepath = File.join('/', project_name, 'IN', filename_split)
bookmaker_authkeys_dir = File.join(File.dirname(__FILE__), '../bookmaker_authkeys')
generated_access_token = File.read("#{bookmaker_authkeys_dir}/access_token.txt")
tmp_dir=File.join(working_dir, basename_normalized)
#testing_value_file = File.join("C:", "staging.txt")
testing_value_file = File.join("C:", "nothing.txt")
errlog = false
errFile = File.join(inbox, "ERROR_RUNNING_#{filename_normalized}.txt")


# ---------------------- LOGGING
logfolder = File.join(working_dir, 'logs')
logfile = File.join(logfolder, "#{basename_normalized}_log.txt")
logger = Logger.new(logfile)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{progname} -- #{msg}\n"
end

#--------------------- RUN
completed_message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: #{project_name} has completed for #{filename_normalized}

#{project_name} has finished running on file #{filename_normalized}.
Both your original file and the updated 'DONE' file are now located in the #{project_name}/OUT Dropbox folder.
MESSAGE_END

error_messageIN = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ERROR running #{project_name} on #{filename_split}

An error occurred while attempting to run #{project_name} on your file #{filename_split}.
Your file was not a .doc or .docx and could not be processed.  
#{filename_split} and the error notification can be found in the #{project_name}/IN Dropbox folder
MESSAGE_END

error_messageOUT = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ERROR running #{project_name} on #{filename_split}

An error occurred while attempting to run #{project_name} on your file #{filename_split}.
Both your original file and the error notice are now located in the #{project_name}/OUT Dropbox folder.
MESSAGE_END


if filename_normalized =~ /^.*_IN_PROGRESS.txt/ || filename_normalized =~ /ERROR_RUNNING_.*.txt/
	logger.info('validator_mailer') {"this is a validator marker file, skipping (e.g. IN_PROGRESS or ERROR_RUNNING_)"}	
else
	#get Dropbox document 'modifier' via api
	client = DropboxClient.new(generated_access_token)
	root_metadata = client.metadata(dropbox_filepath)
	user_email = root_metadata["modifier"]["email"]
	user_name = root_metadata["modifier"]["display_name"]
	logger.info('validator_mailer') {"file modifier detected, display name: #{user_name}, email: #{user_email}"}

	#writing user info from Dropbox API to json - OPTIONAL -could add timestamp to filename (for ones that error and get dumped in logfolder?)
	userinfo_json = File.join(tmp_dir, "userinfo.json")
	datahash = {}
	datahash.merge!(display_name: user_name)
	datahash.merge!(email: user_email)
	finaljson = JSON.generate(datahash)
	# Printing the final JSON object
	File.open(userinfo_json, 'w+:UTF-8') do |f|
	  f.puts finaljson
	end

	#check for errlog in tmp_dir:
	Find.find(tmp_dir) { |file|
		if file =~ /^.*\.(txt|json|log)/ && file !~ /^.*userinfo.json/
			logger.info('validator_mailer') {"error log found in tmpdir: #{file}"}
			errlog = true
		end
	}

	#set appropriate email text based on presence of /IN/errfile or /tmpdir/errlog
	if errlog
		message = error_messageOUT
		logger.info('validator_mailer') {"error log found in tmpdir, setting email text accordingly"}	
	elsif File.file?(errFile)	
		message = error_messageIN
		logger.info('validator_mailer') {"error log in project inbox, setting email text accordingly"}	
	else	
		message = completed_message
		logger.info('validator_mailer') {"No errors found, setting email text accordingly"}	
	end
	#could add a check for done file and a case where only we get alerts if something looks weird.

	#sending mail:
	unless File.file?(testing_value_file)
	  Net::SMTP.start('10.249.0.12') do |smtp|
	  #  smtp.send_message message, 'workflows@macmillan.com', 
	  #                             'workflows@macmillan.com'
  	  smtp.send_message message, 'matthew.retzer@macmillan.com', 
	                              'matthew.retzer@macmillan.com'
	  end
	end
	###multiple recipients example
	 #  smtp.send_message msgstr,
	 #                    'from@example.com',
	 #                    ['dest@example.com', 'dest2@example.com']
	logger.info('validator_mailer') {"sent email, exiting mailer"}	 
end	


