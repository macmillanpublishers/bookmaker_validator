require 'fileutils'
require 'net/smtp'
require 'json'
require 'open3'
require 'find'

module Vldtr
  class Tools

	def self.write_json(hash, json)
	    finaljson = JSON.pretty_generate(hash)
	    File.open(json, 'w+:UTF-8') { |f| f.puts finaljson }
	end

	def self.update_json(newhash, currenthash, json)
    	currenthash.merge!(newhash)
    	Vldtr::Tools.write_json(currenthash,json)
	end

	def self.sendrescue_mail(orig_to,orig_ccs,orig_header)
		begin
message = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ALERT: automated mail failed to send!

This mail is an alert that an automated mail failed to send.
Original addressee was: #{orig_to}
Original cc addresses were: #{orig_ccs}
Original header was: #{orig_header}
MESSAGE_END
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
  def self.move_old_outfiles(outfolder,newfolder)
   	prev_runs=File.join(outfolder,'previous_runs')
   	FileUtils.mkdir_p newfolder
   	Find.find(outfolder) { |f|
      #the regex below is necessary to strip out parens- otherwise the match fails even with the regexp.escape. Ditto line 104)
      Find.prune if f.gsub(/(\(|\))/,"") =~ /#{Regexp.escape(prev_runs.gsub(/(\(|\))/,""))}/
      if f != outfolder
        FileUtils.mv f, newfolder
      end
   	}
   end
   def self.setup_outfolder(outfolder)
   	prev_runs=File.join(outfolder,'previous_runs')
    pr_prefix='run'
   	new_prevrun=File.join(prev_runs,pr_prefix)
   	if File.directory?(outfolder)
   		if !(Dir.entries(outfolder) - %w{ . .. .DS_Store previous_runs }).empty?
   			if !File.directory?(prev_runs)
     			move_old_outfiles(outfolder,"#{new_prevrun}_1")  #may or may not work
   			else
   				pr_counts = [0]
          Find.find(prev_runs) { |f|
   					if File.directory?(f)
   						Find.prune if f.gsub(/(\(|\))/,"") =~ /#{Regexp.escape(new_prevrun.gsub(/(\(|\))/,""))}.*[\\\/]./
              if f =~ /(\/|\\)#{pr_prefix}_\d+$/
  							pr_counts << f.match(/#{pr_prefix}_(\d+)$/)[1].to_i
  						end
   					end
   				}
 					runcount = pr_counts.sort.pop + 1
 					move_old_outfiles(outfolder,"#{new_prevrun}_#{runcount}")
   			end
   		end
   	else
   		FileUtils.mkdir_p outfolder
   	end
   end
  end
end
