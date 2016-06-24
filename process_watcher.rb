require 'fileutils'
require 'json'
require 'net/smtp'
require_relative './validator_tools.rb'

#--------------------- HEADER - main declarations
unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
input_file = File.expand_path(unescapeargv)
input_file = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
filename_normalized = filename_split.gsub(/[^[:alnum:]\._-]/,'')
project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
timestamp = ARGV[1]
logfolder = File.join('S:','resources','logs')
process_logfolder = File.join(logfolder,'processLogs')
json_logfile = File.join(logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.json")
human_logfile = File.join(logfolder,"#{filename_normalized}_out-err_validator_#{timestamp}.txt")
p_logfile = File.join(process_logfolder,"#{filename_normalized}-validator-plog_#{timestamp}.txt")
validator_dir = File.join('S:','resources','bookmaker_scripts','bookmaker_validator')
testing_value_file = File.join("C:", "staging.txt")
#testing_value_file = File.join("C:", "stagasdsading.txt")   #for testing mailer on staging server
thisscript = File.basename($0,'.rb')

#------ local var names
json_exist = true
deploy_complete = true
sleeptime=600
#sleeptime = 2		For testing. can also deliberately hang the ps1 script by commenting out line 48 in deploy.rb ("stdin.close")
sleepmin=sleeptime/60


#--------------------- RUN
sleep(sleeptime)

#load info from json_logfile
if File.file?(json_logfile)
	file = File.open(json_logfile, "r:utf-8")
	content = file.read
	file.close
	jsonlog_hash = JSON.parse(content)
	deploy_complete = jsonlog_hash['completed']
else 
	json_exist = false
end


if !json_exist

	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: #{project_name} ERROR for #{filename_normalized}

#{project_name}'s process watcher waited #{sleepmin} and checked for logs from the deploy.rb file..

No json log is found. 
(should be at: #{json_logfile})
MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
		Vldtr::Tools.sendmail(message,'workflows@macmillan.com','')		
	end
end	


if json_exist && !deploy_complete
	if !File.file?(human_logfile)
		humanreadie = jsonlog_hash.map{|k,v| "#{k} = #{v}"}
		File.open(human_logfile, 'w+:UTF-8') { |f| f.puts humanreadie }
	end	
	attachment = human_logfile
	# Read a file and encode it into base64 format for attaching
	filecontent = File.read(attachment)
	encodedcontent = [filecontent].pack("m")   # base64
	marker = "zzzzzzzzzz"
	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: #{project_name} ERROR for #{filename_normalized}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=#{marker}
--#{marker}
Content-Type: text/plain
Content-Transfer-Encoding:8bit

#{project_name}'s process watcher waited #{sleepmin} minutes and found this run of #{project_name}'s Deploy.rb not yet complete.
Please see attached logfile.

--#{marker}
Content-Type: multipart/mixed; name=\"#{attachment}\"
Content-Transfer-Encoding:base64
Content-Disposition: attachment; filename="#{attachment}"

#{encodedcontent}
--#{marker}--

MESSAGE_END

	#now sending
	unless File.file?(testing_value_file)
		Vldtr::Tools.sendmail(message,'workflows@macmillan.com','')	
	end
end	




