require 'dropbox_sdk'
# Install this the SDK with "gem install dropbox-sdk"
require 'json'
require 'net/smtp'
require 'logger'
require 'find'

#for testing on staging:
#remember to update testing_value_file (line 31 / 32)

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

	#Getting ready to send email
	#set appropriate email text based on presence of /IN/errfile or /tmpdir/errlog
	if errlog
		logger.info('validator_mailer') {"error log found in tmpdir, setting email text accordingly"}	
		subject="#{project_name} has completed for #{filename_normalized}"
		body_a="#{project_name} has finished running on file #{filename_normalized}."
		body_b="Both your original file and the updated 'DONE' file are now located in the \'#{project_name}/OUT\' Dropbox folder."
	elsif File.file?(errFile)	
		logger.info('validator_mailer') {"error log in project inbox, setting email text accordingly"}	
		subject="ERROR running #{project_name} on #{filename_split}"
		body_a="Unable to run #{project_name} on file #{filename_split}: this file is not a .doc or .docx and could not be processed."
		body_b="#{filename_split} and the error notification can be found in the \'#{project_name}/IN\' Dropbox folder"		
	else	
		logger.info('validator_mailer') {"No errors found, setting email text accordingly"}	
		subject="ERROR running #{project_name} on #{filename_split}"
		body_a="An error occurred while attempting to run #{project_name} on your file #{filename_split}."
		body_b="Both your original file and the error notice are now located in the \'#{project_name}/OUT\' Dropbox folder."		
	end

	#setting up handling for additional cc's:
	cc_email=''
	cc_name=''
	cc_address="Cc: Workflows <workflows@macmillan.com>"
	if cc_email != '' then cc_address="#{cc_address}, #{cc_name} <#{cc_email}>" end	

message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
#{cc_address}
Subject: #{subject}

#{body_a}

#{body_b}
MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
	  Net::SMTP.start('10.249.0.12') do |smtp|
  	  smtp.send_message message, 'workflows@macmillan.com', 
	                              user_email, 'workflows@macmillan.com'#, cc_email
	  end
	end
	logger.info('validator_mailer') {"sent email, exiting mailer"}	 
end	


