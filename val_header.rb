require 'fileutils'
require 'logger'
require 'find'
require 'json'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'

module Val
	class Doc
		@unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
		@input_file = File.expand_path(@unescapeargv)
		@@input_file = @input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
		def self.input_file
			@@input_file
		end
		#reinsert !'s and "'" that the .bat replaced with tags
		@@input_file_untag_chars = @@input_file.gsub(/\+\+\+S\+QUOTE\+\+\+/,"'").gsub(/\+\+\+EXCLM\+\+\+/, "!")
		#replace smart quotes that the .bat ignored / mis-substituted with mystery chars
		@infile_char_array = @@input_file_untag_chars.encode!("utf-8").unpack("U*")
		@infile_char_array.each_with_index { |c,index|
			if 230 == c.to_i then @@input_file_untag_chars[index]="‘" end
			if 198 == c.to_i then @@input_file_untag_chars[index]="’" end
			if 244 == c.to_i then @@input_file_untag_chars[index]="“" end
			if 246 == c.to_i then @@input_file_untag_chars[index]="”" end
		}
		def self.input_file_untag_chars
			@@input_file_untag_chars
		end
		@@filename_split = input_file_untag_chars.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
		def self.filename_split
			@@filename_split
		end
		@basename = File.basename(@@filename_split, ".*")
		@@basename_normalized = @basename.gsub(/\W/,"")
		def self.basename_normalized
			@@basename_normalized
		end
		@@extension = File.extname(@@filename_split)
		def self.extension
			@@extension
		end
		@@filename_normalized = "#{@@basename_normalized}#{@@extension}"
		def self.filename_normalized
			@@filename_normalized
		end
		@@filename_docx = "#{@@basename_normalized}.docx"
		def self.filename_docx
			@@filename_docx
		end
		@@converted_docx_filename = "#{@@basename_normalized}_converted.docx"
		def self.converted_docx_filename
			@@converted_docx_filename
		end
    # capture args for _direct_ (non-dropbox) runs
    unless ARGV[1].nil?
      @@runtype = ARGV[1]
    else
      @@runtype = 'dropbox'
    end
    def self.runtype
			@@runtype
		end
    unless ARGV[2].nil?
      @@user_email = ARGV[2]
    else
      @@user_email = ''
    end
    def self.user_email
			@@user_email
		end
    unless ARGV[3].nil?
      @@user_name = ARGV[3]
    else
      @@user_name = 'dropbox'
    end
    def self.user_name
			@@user_name
		end
	end
	class Paths
		@@testing_value_file = File.join("C:", "staging.txt")
		def self.testing_value_file
			@@testing_value_file
		end
		@@working_dir = File.join('S:', 'validator_tmp')
		if Doc.runtype == 'direct'
			@@working_dir = File.join('S:', 'validator_tmp', 'validator_direct')  #<< drive
		end
		def self.working_dir
			@@working_dir
		end
		@@base_logdir = File.join('S:', 'validator_logs')
		def self.base_logdir
			@@base_logdir
		end
		@@bookmaker_scripts_dir = File.join('S:', 'resources', 'bookmaker_scripts')
		def self.bookmaker_scripts_dir
			@@bookmaker_scripts_dir
		end
		@@scripts_dir = File.join(bookmaker_scripts_dir, 'bookmaker_validator')
		# @@scripts_dir = File.join(File.dirname(__FILE__))  # for testing on Mac
		def self.scripts_dir
			@@scripts_dir
		end
    # if Doc.runtype == 'dropbox'
		  @@server_dropfolder_path = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)')
    # elsif Doc.runtype == 'direct'
      # @@server_dropfolder_path = File.join('G:','My Drive','Workflow Tools')  #<< drive
    # end
		def self.server_dropfolder_path
			@@server_dropfolder_path
		end
		@@static_data_files = File.join(server_dropfolder_path,'static_data_files')
		def self.static_data_files
			@@static_data_files
		end
		@@project_dir = Doc.input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
		def self.project_dir
			@@project_dir
		end
		@@project_name = Doc.input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
		def self.project_name
			@@project_name
		end
		@@input_dirname = Doc.input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-1].pop
    def self.input_dirname
			@@input_dirname
		end
		@@tmp_dir=File.join(working_dir, Doc.basename_normalized)
		if Doc.runtype == 'direct'
    	@@tmp_dir = File.join(working_dir, input_dirname)  #<< drive
    end
		def self.tmp_dir
			@@tmp_dir
		end
		@@tmp_original_dir=File.join(@@tmp_dir, 'original_file')
		def self.tmp_original_dir
			@@tmp_original_dir
		end
		@@mailer_dir = File.join(scripts_dir,'mailer_messages')
		def self.mailer_dir
			@@mailer_dir
		end
	end
	class Files
		@@original_file = File.join(Paths.tmp_original_dir, Doc.filename_normalized)
		def self.original_file
			@@original_file
		end
		@@working_file = File.join(Paths.tmp_dir, Doc.filename_docx)
		def self.working_file
			@@working_file
		end
		@@html_output = File.join(Paths.tmp_dir, "#{Doc.basename_normalized}.html")
		def self.html_output
			@@html_output
		end
		@@bookinfo_file = File.join(Paths.tmp_dir,'book_info.json')
		def self.bookinfo_file
			@@bookinfo_file
		end
		@@stylecheck_file = File.join(Paths.tmp_dir,'style_check.json')
		def self.stylecheck_file
			@@stylecheck_file
		end
		@@stylereport_json = File.join(Paths.tmp_dir,'stylereport.json')
		def self.stylereport_json
			@@stylereport_json
		end
		@@stylereport_txt = File.join(Paths.tmp_dir,"#{Doc.basename_normalized}_ValidationReport.txt")
		def self.stylereport_txt
			@@stylereport_txt
		end
		@@contacts_file = File.join(Paths.tmp_dir,'contacts.json')
		def self.contacts_file
			@@contacts_file
		end
		@@status_file = File.join(Paths.tmp_dir,'status_info.json')
		def self.status_file
			@@status_file
		end
		@@isbn_file = File.join(Paths.tmp_dir,'isbn_check.json')
		def self.isbn_file
			@@isbn_file
		end
		@@alerts_json = File.join(Paths.tmp_dir,'alerts.json')
		def self.alerts_json
			@@alerts_json
		end
		@@alerts_json = File.join(Paths.tmp_dir,'alerts.json')
		def self.alerts_json
			@@alerts_json
		end
		@@alertmessages_file = File.join(Paths.mailer_dir,'warning-error_text.json')
		def self.alertmessages_file
			@@alertmessages_file
		end
		@@typesetfrom_file = File.join(Paths.static_data_files,'typeset_from_report','typeset_from.xml')
		def self.typesetfrom_file
			@@typesetfrom_file
		end
		@@imprint_defaultPMs = File.join(Paths.bookmaker_scripts_dir, 'bookmaker_authkeys', 'egalleymaker_staff_list','defaults.json')
		def self.imprint_defaultPMs
			@@imprint_defaultPMs
		end
		@@staff_emails = File.join(Paths.bookmaker_scripts_dir, 'bookmaker_authkeys', 'egalleymaker_staff_list','staff_email.json')
		def self.staff_emails
			@@staff_emails
		end
		@@inprogress_file = File.join(Paths.project_dir,"#{Doc.filename_normalized}_IN_PROGRESS.txt")
		def self.inprogress_file
			@@inprogress_file
		end
		@@errFile = File.join(Paths.project_dir, "ERROR_RUNNING_#{Doc.filename_normalized}.txt")
		def self.errFile
			@@errFile
		end
		@@section_start_rules_json = File.join(Paths.scripts_dir, "section_start_rules.json")
		def self.section_start_rules_json
			@@section_start_rules_json
		end
    @@epub_outputdir_json = File.join(Paths.bookmaker_scripts_dir, "bookmaker_connectors", "bookmakerbot_outputdirs.json")
    def self.epub_outputdir_json
			@@epub_outputdir_json
		end
    @@papercopyedit_exceptions_json = File.join(Paths.scripts_dir, "papercopyedit_exceptions.json")
    def self.papercopyedit_exceptions_json
			@@papercopyedit_exceptions_json
		end
	end
	class Hashes
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
		def self.status_hash
			readjson(Files.status_file)
		end
		def self.contacts_hash
			readjson(Files.contacts_file)
		end
		def self.bookinfo_hash
			readjson(Files.bookinfo_file)
		end
		def self.stylereport_hash
			readjson(Files.stylereport_json)
		end
		def self.isbn_hash
			readjson(Files.isbn_file)
		end
		def self.staff_hash
			readjson(Files.staff_emails)
		end
		def self.staff_defaults_hash
			readjson(Files.imprint_defaultPMs)
		end
		def self.alerts_hash
			readjson(Files.alerts_json)
		end
		def self.alertmessages_hash
			readjson(Files.alertmessages_file)
		end
    def self.epub_outputdir_hash
      readjson(Files.epub_outputdir_json)
    end
    def self.papercopyedit_exceptions_hash
      readjson(Files.papercopyedit_exceptions_json)
    end
	end
	class Resources
    @@emailtest_recipient = 'workflows@macmillan.com'
    def self.emailtest_recipient
			@@emailtest_recipient
		end
    # MR-4-20\/ this legacy testing protoc0l involved setting this value to 'true' but renaming staging file.
    # => so we get all mailers but retain staging directories. Not ideal. Using dummy recipient for staging instead^^
    #this allows to test all mailers on staging but still utilize staging (Dropbox & Coresource) paths
    #it's only called in validator_cleanup & posts_cleanup
    @@testing = false
		def self.testing
			@@testing
		end
		@@thisscript = File.basename($0,'.rb')
		def self.thisscript
			@@thisscript
		end
		@@run_macro_ps = File.join(Paths.scripts_dir,'run_macro.ps1')
		def self.run_macro_ps
			@@run_macro_ps
		end
		@@powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
		def self.powershell_exe
			@@powershell_exe
		end
		# # \/ use installed ruby from PATH
		@@ruby_exe = 'ruby'
		# # \/ use ruby version at specific path
		# @@ruby_exe = File.join('C:','Ruby200','bin','ruby.exe')
		def self.ruby_exe
			@@ruby_exe
		end
		@@authkeys_repo = File.join(Paths.scripts_dir,'..','bookmaker_authkeys')
		def self.authkeys_repo
			@@authkeys_repo
		end
    @@smtp_address = File.read(File.join(authkeys_repo,'smtp.txt')).strip
		def self.smtp_address
			@@smtp_address
		end
		@@rs_ftp_creds_hash = Mcmlln::Tools.readjson(File.join(authkeys_repo,'rs_ftp_creds.json'))
		def self.rs_ftp_creds_hash
			@@rs_ftp_creds_hash
		end
		@@generated_access_token_file = File.join(authkeys_repo,'access_token.txt')
		def self.generated_access_token_file
			@@generated_access_token_file
		end
		def self.mailtext_gsubs(mailtext,alerts,bookinfo)
				 updated_txt = mailtext.gsub(/FILENAME_NORMALIZED/,Doc.filename_normalized).gsub(/FILENAME_SPLIT/,Doc.filename_normalized).gsub(/PROJECT_NAME/,Paths.project_name).gsub(/ALERTS/,alerts).gsub(/BOOKINFO/,bookinfo)
				updated_txt
		end
	end
	class Logs
		@@logfilename = "#{Doc.basename_normalized}_log.txt"
		if Doc.runtype == 'direct'
			@@logfilename = "#{Paths.input_dirname}_log.txt"  # < unique logname from api_timestamp
		end
		def self.logfilename
			@@logfilename
		end
		def self.setlogfolders(projectname)
			@dropfolder_logdir = File.join(Paths.server_dropfolder_path, 'bookmaker_logs', projectname)
			@logfolder = File.join(@dropfolder_logdir, 'logs')
			@permalog = File.join(@dropfolder_logdir,'validator_history_report.json')
			@deploy_logfolder = File.join(@dropfolder_logdir, 'std_out-err_logs')
			if Doc.runtype == 'direct'
				@logfolder = File.join(Paths.base_logdir, 'logs')
				@permalog = File.join(Paths.base_logdir,'validator_history_report.json')
				@deploy_logfolder = File.join(Paths.base_logdir, 'std_out-err_logs')
			end
			# if !File.directory?(@deploy_logfolder)	then FileUtils.mkdir_p(@deploy_logfolder) end
			@json_logfile = File.join(@deploy_logfolder,"#{Doc.filename_normalized}_out-err_validator.json")
			@human_logfile = File.join(@deploy_logfolder,"#{Doc.filename_normalized}_out-err_validator.txt")
			@process_logfile = File.join(@deploy_logfolder,"#{projectname}--processlog.txt")
			return @logfolder, @permalog, @deploy_logfolder, @json_logfile, @human_logfile, @process_logfile
		end
		@@logfolder, @@permalog, @@deploy_logfolder, @@json_logfile, @@human_logfile, @@process_logfile = setlogfolders(Paths.project_name)
		def self.logfolder
			@@logfolder
		end
		def self.permalog
			@@permalog
		end
		def self.deploy_logfolder
			@@deploy_logfolder
		end
		def self.json_logfile
			@@json_logfile
		end
		def self.human_logfile
			@@human_logfile
		end
		def self.process_logfile
			@@process_logfile
		end
		@@orig_std_out = $stdout.clone   #part I: redirecting console output to logfile
		def self.orig_std_out
			@@orig_std_out
		end
		def self.redirect_stdOutErr(logfile)
			$stdout.reopen(File.open(logfile, 'a'))
			$stdout.sync = true
			$stderr.reopen($stdout)
		end
		def self.return_stdOutErr
			$stdout.reopen(@@orig_std_out)
			$stdout.sync = true
			$stderr.reopen($stdout)
		end
		@@std_logfile = ''
		def self.log_setup(file=logfilename,folder=logfolder)		#can be overwritten in function call
			if !File.directory?(folder)	then FileUtils.mkdir_p(folder) end
			logfile = File.join(folder,file)
			#part II: redirecting console output to logfile
			Val::Logs.redirect_stdOutErr(logfile)
			@@logger = Logger.new(logfile)
			def self.logger
				@@logger
			end
			logger.formatter = proc do |severity, datetime, progname, msg|
				"#{datetime}: #{Resources.thisscript.upcase} -- #{msg}\n"
			end
			@@std_logfile = logfile
			def self.std_logfile
				@@std_logfile
			end
		end
	end
	class Posts
		@lookup_isbn = Doc.basename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
		@@index = Doc.basename_normalized.split('_').last
		def self.index
			@@index
		end
		@@tmp_dir = File.join(Paths.working_dir, "#{@lookup_isbn}_to_bookmaker_#{@@index}")
		def self.tmp_dir
			@@tmp_dir
		end
		@@tmp_original_dir=File.join(@@tmp_dir, 'original_file')
		def self.tmp_original_dir
			@@tmp_original_dir
		end
		@@bookinfo_file = File.join(tmp_dir,'book_info.json')
		def self.bookinfo_file
			@@bookinfo_file
		end
		@@contacts_file = File.join(tmp_dir,'contacts.json')
		def self.contacts_file
			@@contacts_file
		end
		@@status_file = File.join(tmp_dir,'status_info.json')
		def self.status_file
			@@status_file
		end
		@@alerts_json = File.join(tmp_dir,'alerts.json')
		def self.alerts_json
			@@alerts_json
		end
		def self.bookinfo  #get info from bookinfo.json.  Putting this in Posts instead of resources so Posts.bookinfo is already defined
				if Resources.thisscript =~ /post_/ && Doc.runtype != 'direct'
					info_file = Posts.bookinfo_file
				else
					info_file = Files.bookinfo_file
				end
				if File.file?(info_file)
					bookinfo_hash = Mcmlln::Tools.readjson(info_file)
					work_id = bookinfo_hash['work_id']
					author = bookinfo_hash['author']
					title = bookinfo_hash['title']
					imprint = bookinfo_hash['imprint']
					product_type = bookinfo_hash['product_type']
					bookinfo_isbn = bookinfo_hash['isbn']
					bookinfo_pename = bookinfo_hash['production_editor']
					bookinfo_pmname = bookinfo_hash['production_manager']
					bookinfo="ISBN lookup for #{bookinfo_isbn}:\nTITLE: \"#{title}\"\nAUTHOR: \'#{author}\'\nIMPRINT: \'#{imprint}\'\nPRODUCT-TYPE: \'#{product_type}\'\n"
				else
					bookinfo=''
				end
				return bookinfo
		end
		@@converted_file, @@stylereport_txt, @@val_infile_name, @@logfile_name = '','','infile_not_present',Logs.logfilename
		if Dir.exists?(tmp_dir)
			Find.find(tmp_dir) { |file|
			if file !~ /_DONE_#{index}#{Doc.extension}$/# && File.extname(file) =~ /.doc($|x$)/
				if file =~ /(_converted)*#{Doc.extension}$/
					@@converted_file = file
				elsif file =~ /_ValidationReport\.txt$/
					@@stylereport_txt = file
				else
					@@val_infile_name = file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
				end
			end
			}
			def self.val_infile_name
				@@val_infile_name
			end
			def self.stylereport_txt
				@@stylereport_txt
			end
			@@logfile_name = File.basename(@@converted_file, ".*").sub(/(_converted)*$/,'_log.txt')
			def self.logfile_name
				@@logfile_name
			end
			@projectname = ''
			if File.file?(Paths.testing_value_file) || Resources.testing == true
				@projectname = 'egalleymaker_stg'
			else
				@projectname = 'egalleymaker'
			end
			@@logfolder, @@permalog, @deploy_logfolder, @@json_logfile, @human_logfile, @process_logfile = Logs.setlogfolders(@projectname)
			def self.logfolder
				@@logfolder
			end
			def self.json_logfile
				@@json_logfile
			end
			def self.permalog
				@@permalog
			end
			@@process_logfile = @process_logfile.gsub(/--processlog.txt/,'-posts-processlog.txt')
			def self.process_logfile
				@@process_logfile
			end
		end
	end
end
