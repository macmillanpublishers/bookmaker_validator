require 'fileutils'
require 'net/smtp'
require 'json'
require 'open3'
require 'find'

require_relative './val_header.rb'
require_relative '../bookmaker/core/header.rb'

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
Dropbox api lookup failed for file \"#{Val::Doc.filename_normalized}\"
(found email address \"#{user_email}\").
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
      deploy_err_text = <<MESSAGE_END
From: Workflows <workflows@macmillan.com>
To: Workflows <workflows@macmillan.com>
Subject: ALERT: #{Val::Paths.project_name} process crashed
#{Val::Resources.thisscript}.rb has crashed during #{Val::Paths.project_name} run.
Please see the following logfiles for assistance in troubleshooting
- #{Val::Logs.logfolder}/#{Val::Logs.logfilename}
- #{Val::Logs.deploy_logfolder}/#{Val::Logs.json_logfile}
MESSAGE_END
      deploy_err_text
    end
  end
  class Tools
    def self.dropbox_api_call
      py_script = File.join(Val::Paths.scripts_dir,'dboxapi2.py')
      dropbox_filepath = File.join('/', Val::Paths.project_name, 'IN', Val::Doc.filename_split).gsub(/(&)/,'\\\\\1')
      generated_access_token = File.read(Val::Resources.generated_access_token_file)
      #run python api script
      dropboxmodifier = Bkmkr::Tools.runpython(py_script, "#{generated_access_token} #{dropbox_filepath}")
      if dropboxmodifier.nil? or dropboxmodifier.empty? or !dropboxmodifier
        user_email, user_name = '', ''
      else
        user_email = dropboxmodifier.split(' ', 2)[0]
        user_name = dropboxmodifier.split(' ', 2)[1].gsub(/\n/,'')
      end
      return user_email, user_name
    rescue Exception => e
      p e   #puts e.inspect
    end
    def self.write_json(hash, json)
      finaljson = JSON.pretty_generate(hash)
      File.open(json, 'w+:UTF-8') { |f| f.puts finaljson }
    end
    def self.update_json(newhash, currenthash, json)
      currenthash.merge!(newhash)
      Vldtr::Tools.write_json(currenthash,json)
    end
    # expecting alert_type of "error", "warning", or "notice", but will accept anything.
    def self.log_alert_to_json(alerts_json, alert_category, new_errtext)
        alerts_hash = Mcmlln::Tools.readjson(alerts_json)
        if alerts_hash.has_key? alert_category
            alerts_hash[alert_category].push(new_errtext)
        else
            alerts_hash[alert_category]=[]
            alerts_hash[alert_category].push(new_errtext)
        end
        Vldtr::Tools.write_json(alerts_hash, alerts_json)
    end
    def self.get_alert_string(alerts_json)
        alerts_hash = Mcmlln::Tools.readjson(alerts_json)
        alerttxt_string = ""
        alerttxt_list = []
        unless alerts_hash.empty?
            # make sure errors come first
            alerts_hash = Hash[alerts_hash.sort]
            # cycle through the hash and write the formatted key (category) folloed by values
            alerts_hash.each { |category, errlist|
                if category == 'error'
                  cat_string = "#{category.upcase}(s): #{Val::Hashes.alertmessages_hash['errors']['error_header']['message']}"
                else
                  cat_string = "#{category.upcase}(s):"
                end
                alerttxt_list.push(cat_string)
                errlist.each { |errtext|
                  alerttxt_list.push("- #{errtext}")
                }
                alerttxt_list.push("")
            }
            alerttxt_string = alerttxt_list.join("\n")
        end
        return alerttxt_string, alerts_hash
    end
    def self.write_alerts_to_txtfile(alerts_json, outfolder)
        alerttxt_string, alerts_hash = Vldtr::Tools.get_alert_string(alerts_json)
        # now we figure outwhat to call the file, based on highest level of alert
        if alerts_hash.has_key? "error"
            alertfile = File.join(outfolder, "ERROR.txt")
        elsif alerts_hash.has_key? "warning"
            alertfile = File.join(outfolder, "WARNING.txt")
        else
            alertfile = File.join(outfolder, "NOTICE.txt")
        end
        # write our file
        File.open(alertfile, "w") do |f|
            f.puts(alerttxt_string)
        end
        return alertfile
    end
    def self.sendrescue_mail(orig_to,orig_ccs,orig_header)
    message = Mailtexts.rescuemail(orig_to,orig_ccs,orig_header)
    Net::SMTP.start(Val::Resources.smtp_address) do |smtp|
        smtp.send_message message, 'workflows@macmillan.com',
                                  'workflows@macmillan.com'
    end
    rescue Exception => e
    p e   #puts e.inspect
    end
    def self.sendmail(message, to_email, cc_emails)
    	if cc_emails.empty?
      		Net::SMTP.start(Val::Resources.smtp_address) do |smtp|
    	  		smtp.send_message message, 'workflows@macmillan.com',
                                  		to_email
      		end
    	else
      		Net::SMTP.start(Val::Resources.smtp_address) do |smtp|
    	  		smtp.send_message message, 'workflows@macmillan.com',
                                  		to_email, cc_emails
    	  	end
      end
    rescue Exception => e
      p e   #puts e.inspect
      puts "Original mail failed, now attempting to send alertmail to workflows:"
      sendrescue_mail(to_email,cc_emails,message.lines[0..3])
    end
    def self.ebooks_mail_check()  #alternate will always be submitter, so far om is std_recipient in all cases
      if Val::Hashes.contacts_hash['ebooksDept_submitter'] == true || File.file?(Val::Paths.testing_value_file)
        user_name = Val::Hashes.contacts_hash['submitter_name']
        user_email = Val::Hashes.contacts_hash['submitter_email']
      else
        user_name = Val::Hashes.contacts_hash["production_manager_name"]
        user_email = Val::Hashes.contacts_hash["production_manager_email"]
      end
      return user_name, user_email
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
      Open3.popen2e(command.join(" ")) do |stdin, stdouterr, wait_thr|
      stdin.close
      stdouterr.each { |line|
        alloutput << line
        }
      end
      outputhash={ "#{scriptname}" => alloutput }
      update_json(outputhash, hash, jsonlog)
      log_time(hash,scriptname,'completion time',jsonlog)
    end
    def self.run_macro(logger,macro_name)
      macro_output = ''
      Val::Logs.return_stdOutErr  #stop console log redirect to file
      #run macro
      Open3.popen2e("#{Val::Resources.powershell_exe} \"#{Val::Resources.run_macro_ps} \'#{Val::Files.working_file}\' \'#{macro_name}\' \'#{Val::Logs.std_logfile}\'\"") do |stdin, stdouterr, wait_thr|
          stdin.close
          stdouterr.each { |line|
              macro_output << line
          }
      end
      Val::Logs.redirect_stdOutErr(Val::Logs.std_logfile)  #turn console log redirect back on
      logger.info {"finished running #{macro_name} macro"}
      macro_output
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
    def self.runpython(py_script, args)
      #stop console log redirect to file
      Val::Logs.return_stdOutErr
      # select python path and run script
      if Bkmkr::Tools.os == "mac" or Bkmkr::Tools.os == "unix"
        `python #{py_script} #{args}`
      elsif Bkmkr::Tools.os == "windows"
        pythonpath = File.join(Bkmkr::Paths.resource_dir, "Python27", "python.exe")
        py_output = `#{pythonpath} #{py_script} #{args}`
      else
        py_output = "ERROR: I can't seem to run python. Is it installed and part of your system PATH?"
      end
      return py_output
    rescue => e
      p e
    ensure
      #turn console log redirect back on
      Val::Logs.redirect_stdOutErr(Val::Logs.std_logfile)
    end
    def self.runnode(js, args)
      if Bkmkr::Tools.os == "mac" or Bkmkr::Tools.os == "unix"
        node_output = `node #{js} #{args}`
      elsif Bkmkr::Tools.os == "windows"
        nodepath = File.join(Bkmkr::Paths.resource_dir, "nodejs", "node.exe")
        node_output = `#{nodepath} #{js} #{args}`
      else
        node_output = "ERROR: I can't seem to run node. Is it installed and part of your system PATH?"
      end
      return node_output
    rescue => e
      p e
    end
  end
end
