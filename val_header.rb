require 'fileutils'
require 'logger'
require 'find'

module Val
	class Doc
		@unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
  		@input_file = File.expand_path(@unescapeargv)
  		@@input_file = @input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
		def self.input_file
			@@input_file
		end
		@@filename_split = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
		def self.filename_split
			@@filename_split
		end
		@@filename_normalized = filename_split.gsub(/[^[:alnum:]\._-]/,'')
		def self.filename_normalized
			@@filename_normalized
		end
		@@basename_normalized = File.basename(filename_normalized, ".*")
		def self.basename_normalized
			@@basename_normalized
		end
		@@extension = File.extname(filename_normalized)
		def self.extension
			@@extension
		end
	end
	class Paths
		@@testing_value_file = File.join("C:", "staging.txt")
		def self.testing_value_file
			@@testing_value_file
		end
		@@working_dir = File.join('S:', 'validator_tmp')
		def self.working_dir
			@@working_dir
		end
		@@scripts_dir = File.join('S:', 'resources', 'bookmaker_scripts', 'bookmaker_validator')
		def self.scripts_dir
			@@scripts_dir
		end
		@@server_dropbox_path = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)')
		def self.server_dropbox_path
			@@server_dropbox_path
		end
		@@project_dir = Doc.input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
		def self.project_dir
			@@project_dir
		end
		@@project_name = Doc.input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
		def self.project_name
			@@project_name
		end
		@@tmp_dir=File.join(working_dir, Doc.basename_normalized)
		def self.tmp_dir
			@@tmp_dir
		end
		@@mailer_dir = File.join(scripts_dir,'mailer_messages')
		def self.mailer_dir
			@@mailer_dir
		end
	end
	class Files
		@@working_file = File.join(Paths.tmp_dir, Doc.filename_normalized)
		def self.working_file
			@@working_file
		end
		@@bookinfo_file = File.join(Paths.tmp_dir,'book_info.json')
		def self.bookinfo_file
			@@bookinfo_file
		end
		@@stylecheck_file = File.join(Paths.tmp_dir,'style_check.json')
		def self.stylecheck_file
			@@stylecheck_file
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
		@@inprogress_file = File.join(Paths.project_dir,"#{Doc.filename_normalized}_IN_PROGRESS.txt")
		def self.inprogress_file
			@@inprogress_file
		end
		@@errFile = File.join(Paths.project_dir, "ERROR_RUNNING_#{Doc.filename_normalized}.txt")
		def self.errFile
			@@errFile
		end
	end
	class Resources
		@@testing = false			#this allows to test all mailers on staging but still utilize staging (Dropbox & Coresource) paths
		def self.testing			#it's only called in validator_cleanup & posts_cleanup
			@@testing
		end
		@@testing_Prod = false			#this allows to test on prod without emailing Patrick for epubQA
		def self.testing_Prod			
			@@testing_Prod
		end		
		@@pilot = false			#this runs true prod environment, except mails Workflows instead of Westchester & sets pretend coresourceDir
		def self.pilot			
			@@pilot
		end		
		@@thisscript = File.basename($0,'.rb')
		def self.thisscript
			@@thisscript
		end
		@@run_macro = File.join(Paths.scripts_dir,'run_macro.ps1')
		def self.run_macro
			@@run_macro
		end
		@@powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
		def self.powershell_exe
			@@powershell_exe
		end
		@@ruby_exe = File.join('C:','Ruby200','bin','ruby.exe')
		def self.ruby_exe
			@@ruby_exe
		end
		@@authkeys_repo = File.join(Paths.scripts_dir,'..','bookmaker_authkeys')
		def self.authkeys_repo
			@@authkeys_repo
		end
		def self.mailtext_gsubs(mailtext,warnings,errors,bookinfo)
   			updated_txt = mailtext.gsub(/FILENAME_NORMALIZED/,Doc.filename_normalized).gsub(/FILENAME_SPLIT/,Doc.filename_split).gsub(/PROJECT_NAME/,Paths.project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
				updated_txt
		end
	end
	class Logs
		@@dropbox_logfolder = ''
		if File.file?(Paths.testing_value_file)
			@@dropbox_logfolder = File.join(Paths.server_dropbox_path, 'bookmaker_logs', 'bookmaker_validator_stg')
		else
			@@dropbox_logfolder = File.join(Paths.server_dropbox_path, 'bookmaker_logs', 'bookmaker_validator')
		end	
		@@logfolder = File.join(@@dropbox_logfolder, 'logs')		#defaults for logging
		def self.logfolder
			@@logfolder
		end
		@@logfilename = "#{Doc.basename_normalized}_log.txt"
		def self.logfilename
			@@logfilename
		end
		def self.log_setup(file=logfilename,folder=logfolder)		#can be overwritten in function call
			logfile = File.join(folder,file)
			@@logger = Logger.new(logfile)
			def self.logger
				@@logger
			end
			logger.formatter = proc do |severity, datetime, progname, msg|
			  "#{datetime}: #{Resources.thisscript.upcase} -- #{msg}\n"
			end
		end
		@@permalog = File.join(@@dropbox_logfolder,'validator_history_report.json')
		def self.permalog
			@@permalog
		end
		@@deploy_logfolder = File.join(@@dropbox_logfolder, 'std_out-err_logs')
		def self.deploy_logfolder
			@@deploy_logfolder
		end
		@@process_logfolder = File.join(@@dropbox_logfolder, 'process_Logs')
		def self.process_logfolder
			@@process_logfolder
		end
		@@json_logfile = File.join(deploy_logfolder,"#{Doc.filename_normalized}_out-err_validator.json")
		def self.json_logfile
			@@json_logfile
		end
		@@human_logfile = File.join(deploy_logfolder,"#{Doc.filename_normalized}_out-err_validator.txt")
		def self.human_logfile
			@@human_logfile
		end
		@@p_logfile = File.join(process_logfolder,"#{Doc.filename_normalized}-validator-plog.txt")
		def self.p_logfile
			@@p_logfile
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
		@@working_file, @@val_infile_name, @@logfile_name = '','',Logs.logfilename
		if Dir.exists?(tmp_dir)
			Find.find(tmp_dir) { |file|
			if file !~ /_DONE_#{index}#{Doc.extension}$/ && File.extname(file) =~ /.doc($|x$)/
				if file =~ /_workingfile#{Doc.extension}$/
					@@working_file = file
				else
					@@val_infile_name = file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).pop
				end
			end
			}
			def self.working_file
				@@working_file
			end
			def self.val_infile_name
				@@val_infile_name
			end
			@@logfile_name = File.basename(working_file, ".*").gsub(/_workingfile$/,'_log.txt')
			def self.logfile_name
				@@logfile_name
			end
		end
	end
end
