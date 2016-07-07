require 'fileutils'
require 'logger'

#require_relative 'utilities/mcmlln-tools.rb'

module Val
	class Doc
		@unescapeargv = ARGV[0].chomp('"').reverse.chomp('"').reverse
  		@input_file = File.expand_path(@unescapeargv)
  		@@input_file = @input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact)).join(File::SEPARATOR)
		def self.input_file
			@@input_file
		end
		@@input_file_normalized = input_file.gsub(/ /, "")  #is this used anywhere by me?
		def self.input_file_normalized
			@@input_file_normalized
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
	class AbsolutePaths
		@@working_dir = File.join('S:', 'validator_tmp')
		def self.working_dir
			@@working_dir
		end
		#@@validator_dir = File.dirname(__FILE__)
		@@validator_dir = File.join('S:', 'resources', 'bookmaker_scripts', 'bookmaker_validator')
		def self.validator_dir
			@@validator_dir
		end			
		@@scripts_dir = File.join('S:', 'resources', 'bookmaker_scripts', 'bookmaker_validator')
		def self.scripts_dir
			@@scripts_dir
		end		
		@@testing_value_file = File.join("C:", "staging.txt")
		def self.testing_value_file
			@@testing_value_file
		end
		@@server_dropbox_path = File.join('C:','Users','padwoadmin','Dropbox (Macmillan Publishers)')
		def self.server_dropbox_path
			@@server_dropbox_path
		end	
	end	
	class Paths 
		@@project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
		def self.project_dir
			@@project_dir
		end
		@@project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
		def self.project_name
			@@project_name
		end
		@@inbox = File.join(project_dir, 'IN')   #does this get used anywhere?  Could use tmparchive 3rd declaration...
		def self.inbox
			@@inbox
		end
		@@outbox = File.join(project_dir, 'OUT')   #likewise, used?
		def self.outbox
			@@outbox
		end
		@@tmp_dir=File.join(AbsolutePaths.working_dir, basename_normalized)
		def self.tmp_dir
			@@tmp_dir
		end
		@@mailer_dir = File.join(AbsolutePaths.validator_dir,'mailer_messages')		
		def self.mailer_dir
			@@mailer_dir
		end
	end	
	class Files
		@@working_file = File.join(Paths.tmp_dir, filename_normalized)
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
		@@inprogress_file = File.join(Paths.inbox,"#{Doc.filename_normalized}_IN_PROGRESS.txt")
		def self.inprogress_file
			@@inprogress_file
		end	
		@@errFile = File.join(Paths.project_dir, "ERROR_RUNNING_#{Doc.filename_normalized}.txt")
		def self.errFile
			@@errFile
		end	
	end
	class Resources
		@@thisscript = File.basename($0,'.rb')
		def self.thisscript
			@@thisscript
		end
		@@run_macro = File.join(AbsolutePaths.scripts_dir,'run_macro.ps1')
		def self.run_macro
			@@run_macro
		end	
		@@powershell_exe = 'PowerShell -NoProfile -ExecutionPolicy Bypass -Command'
		def self.powershell_exe
			@@powershell_exe
		end
		@@authkeys_repo = File.join(AbsolutePaths.scripts_dir,'..','bookmaker_authkeys')
		def self.authkeys_repo
			@@authkeys_repo
		end	
		def mailtext_gsubs(mailtext,warnings,errors,bookinfo)
   			mailtext.gsub(/FILENAME_NORMALIZED/,Files.working_file).gsub(/FILENAME_SPLIT/,Doc.filename_split).gsub(/PROJECT_NAME/,Paths.project_name).gsub(/WARNINGS/,warnings).gsub(/ERRORS/,errors).gsub(/BOOKINFO/,bookinfo)
		end	
	end
	class Logs
		@@this_dir = File.expand_path(File.dirname(__FILE__))
		@@logfolder = File.join(AbsolutePaths.working_dir, 'logs')		#defaults for logging
		@@logfilename = "#{Doc.basename_normalized}_log.txt"	
		def self.log_setup(file=@@logfilename,folder=@@logfolder)		#can be overwritten in function call
			logfile = File.join(folder,file)
			@@logger = Logger.new(logfile)
			def self.logger
				@@logger
			end	
			logger.formatter = proc do |severity, datetime, progname, msg|
			  "#{datetime}: #{Resources.thisscript} -- #{msg}\n"
			end		
		end
	end		
	class Posts
		@lookup_isbn = Doc.basename_normalized.match(/9(78|-78|7-8|78-|-7-8)[0-9-]{10,14}/).to_s.tr('-','').slice(0..12)
		@@index = Doc.basename_normalized.split('-').last
		def self.index
			@@index
		end	
		@@tmp_dir = File.join(AbsolutePaths.working_dir, "#{@lookup_isbn}_to_bookmaker-#{@@index}")
		def self.tmp_dir
			@@tmp_dir
		end	
		@@bookinfo_file = File.join(@@tmp_dir,'book_info.json')
		def self.bookinfo_file
			@@bookinfo_file
		end
		@@contacts_file = File.join(@@tmp_dir,'contacts.json')
		def self.contacts_file
			@@contacts_file
		end	
		@@status_file = File.join(@@tmp_dir,'status_info.json') 
		def self.status_file
			@@status_file
		end			
		@@working_file, @@val_infile_name = '',''	
		Find.find(@@tmp_dir) { |file|
		if file !~ /_DONE-#{@@index}#{Doc.extension}$/ && File.extname(file) =~ /.doc($|x$)/
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
		@@et_project_dir = ''
		if File.file?(AbsolutePaths.testing_value_file)
			@@et_project_dir = File.join(AbsolutePaths.server_dropbox_path,'egalley_transmittal_stg')
		else
			@@et_project_dir = File.join(AbsolutePaths.server_dropbox_path,'egalley_transmittal')
		end
		def self.et_project_dir
			@@et_project_dir
		end	
		@@logfile_name = File.basename(@@working_file, ".*").gsub(/_workingfile$/,'_log.txt')
		def self.logfile_name
			@@logfile_name
		end	
	end	
end