require 'fileutils'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


#--------------------- LOCAL DECLARATIONS
log_suffix = ARGV[0]
sleepmin = ARGV[1].to_i
sleeptime = sleepmin*60
#For testing: can deliberately hang  ps1 script by commenting out line in open3 call: ("stdin.close")

json_logfile = Val::Logs.json_logfile.gsub(/.json$/,"#{log_suffix}.json")
human_logfile = Val::Logs.human_logfile.gsub(/.txt$/,"#{log_suffix}.txt")

json_exist = true
deploy_complete = true

#--------------------- RUN
sleep(sleeptime)

#load info from json_logfile
if File.file?(json_logfile)
	jsonlog_hash = Mcmlln::Tools.readjson(json_logfile)
	deploy_complete = jsonlog_hash['completed']
else
	json_exist = false
end

if !json_exist
	message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: #{Val::Paths.project_name} ERROR for #{Val::Doc.filename_normalized}

#{Val::Paths.project_name}'s process watcher waited #{sleepmin} and checked for logs from the deploy.rb file..

No json log is found.
(should be at: #{json_logfile})
MESSAGE_END
	#now sending
	if File.file?(Val::Paths.testing_value_file)
    message += "\n\nThis message sent from STAGING SERVER"
  end
  Vldtr::Tools.sendmail(message,'workflows@macmillan.com','')
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
Subject: #{Val::Paths.project_name} ERROR for #{Val::Doc.filename_normalized}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=#{marker}
--#{marker}
Content-Type: text/plain
Content-Transfer-Encoding:8bit

#{Val::Paths.project_name}'s process watcher waited #{sleepmin} minutes and found this run of #{Val::Paths.project_name}'s Deploy.rb not yet complete.
Please see attached logfile.

--#{marker}
Content-Type: multipart/mixed; name=\"#{attachment}\"
Content-Transfer-Encoding:base64
Content-Disposition: attachment; filename="#{attachment}"

#{encodedcontent}
--#{marker}--

MESSAGE_END

	#now sending
	if File.file?(Val::Paths.testing_value_file)
    message += "\n\nThis message sent from STAGING SERVER"
  end
	Vldtr::Tools.sendmail(message,'workflows@macmillan.com','')
end
