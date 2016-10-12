require 'fileutils'
require 'net/smtp'
require 'json'
require 'open3'

require_relative './val_header.rb'

module Vldtr
  class Mailtexts
    def self.generic(user_name,user_email,body)
      message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: #{user_name} <#{user_email}>
CC: Workflows <workflows@macmillan.com>
#{body}
MESSAGE_END
      message
    end
    def self.apifail(user_email)
      message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ERROR: dropbox api lookup failure
Dropbox api lookup failed for file: #{Val::Doc.filename_normalized}. (found email address: \"#{user_email}\")
MESSAGE_END
      message
    end
    def self.rescuemail(orig_to,orig_ccs,orig_header)
      message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ALERT: automated mail failed to send!

This mail is an alert that an automated mail failed to send.
Original addressee was: #{orig_to}
Original cc addresses were: #{orig_ccs}
Original header was: #{orig_header}
MESSAGE_END
      message
    end
    def self.deploy_err_text
      deploy_err_text =<<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ALERT: #{Val::Paths.project_name} process crashed

#{Val::Resources.thisscript}.rb has crashed during #{Val::Paths.project_name} run.

Please see the following logfiles for assistance in troubleshooting:
#{Val::Logs.logfolder}/#{Val::Logs.logfilename}
#{Val::Logs.deploy_logfolder}/#{Val::Logs.json_logfile}
MESSAGE_END
      deploy_err_text
    end
  end
  class Tools
  	def self.write_json(hash, json)
  	    finaljson = JSON.pretty_generate(hash)
  	    File.open(json, 'w+:UTF-8') { |f| f.puts finaljson }
  	end
  	def self.update_json(newhash, currenthash, json)
      	currenthash.merge!(newhash)
      	Vldtr::Tools.write_json(currenthash,json)
  	end
    def self.readjson(inputfile)
      json_hash = {}
      if File.file?(inputfile)
        file = File.open(inputfile, "r:utf-8")
        content = file.read
        file.close
        json_hash = JSON.parse(content)
      end
      json_hash
    end
  	def self.sendrescue_mail(orig_to,orig_ccs,orig_header)
  		begin
        message = Mailtexts.rescuemail(orig_to,orig_ccs,orig_header)
  			Net::SMTP.start('10.249.0.12') do |smtp|
  	  	  	smtp.send_message message, 'workflows@macmillan.com',
  		                              	'workflows@macmillan.com'
  		  	end
  	  	rescue Exception => e
  			p e   #puts e.inspect
  	  	end
  	end
  	def self.sendmail(message, to_email, cc_emails)
  		begin
  			if cc_emails.empty?
  		  		Net::SMTP.start('10.249.0.12') do |smtp|
  	  	  		smtp.send_message message, 'workflows@macmillan.com',
  		                              		to_email
  		  		end
  			else
  		  		Net::SMTP.start('10.249.0.12') do |smtp|
  	  	  		smtp.send_message message, 'workflows@macmillan.com',
  		                              		to_email, cc_emails
  		  		end
  		  	end
  	  	rescue Exception => e
  			p e   #puts e.inspect
  			puts "Original mail failed, now attempting to send alertmail to workflows:"
  			Vldtr::Tools.sendrescue_mail(to_email,cc_emails,message.lines[0..3])
  		end
  	end
  	def self.checkisbn(isbn)
  		isbn.gsub!(/[^0-9,]/,'')
  		isbntwelve = isbn[0..11]
  		i=1
  		sum=0
  		isbntwelve.scan(/\d/) { |int|
  			int=int.to_i
  			 if i%2 == 0 then int=int*3 end
  			 sum=sum+int
  			 i+=1
  		}
      if isbn.length==13 && ((10-(sum%10)) == isbn[12].to_i)
  			cd=true
  		elsif isbn.length==13 && (sum%10) == 0 && isbn[12].to_i == 0
  			cd=true
  		else
  			cd=false
  		end
  		cd
  	end
    def self.log_time(currenthash,scriptname,txt,jsonlog)
    	timestamp_colon = Time.now.strftime('%y%m%d_%H:%M:%S')
    	time_hash = { "#{scriptname} #{txt}" => timestamp_colon }
    	update_json(time_hash,currenthash,jsonlog)
    end
    def self.run_script(command,hash,scriptname,jsonlog)
    	log_time(hash,scriptname,'start time',jsonlog)
    	alloutput = ''
    	Open3.popen2e(command) do |stdin, stdouterr, wait_thr|
    	stdin.close
    	stdouterr.each { |line|
    		alloutput << line
    		}
    	end
    	outputhash={ "#{scriptname}" => alloutput }
    	update_json(outputhash, hash, jsonlog)
    	log_time(hash,scriptname,'completion time',jsonlog)
    end
    def run_macro(logger,macro_name)
      #run macro
      Open3.popen2e("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro_ps} \'#{Val::Files.working_file}\' \'#{macro_name}\' \'#{Val::Logs.std_logfile}\'\"") do |stdin, stdouterr, wait_thr|
          stdin.close
          stdouterr.each { |line|
              macro_output << line
          }
      end
    	logger.info {"finished running #{macro_name} macro"}
      macro_output
    end
  end
end
