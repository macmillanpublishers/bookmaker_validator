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
		@@input_file_normalized = input_file.gsub(/ /, "")
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
		@@testing_value_file = File.join("C:", "staging.txt")
		def self.testing_value_file
			@@testing_value_file
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
		@@inbox = File.join(project_dir, 'IN')
		def self.inbox
			@@inbox
		end
		@@outbox = File.join(project_dir, 'OUT')
		def self.outbox
			@@outbox
		end
		@@tmp_dir=File.join(working_dir, basename_normalized)
		def self.tmp_dir
			@@tmp_dir
		end
		@@mailer_dir = File.join(validator_dir,'mailer_messages')		
		def self.mailer_dir
			@@mailer_dir
		end
	end	
	class Files
		@@working_file = File.join(tmp_dir, filename_normalized)
		def self.working_file
			@@working_file
		end	
		@@bookinfo_file = File.join(tmp_dir,'book_info.json')
		def self.bookinfo_file
			@@bookinfo_file
		end
		@@stylecheck_file = File.join(tmp_dir,'style_check.json')
		def self.stylecheck_file
			@@stylecheck_file
		end	
		@@contacts_file = File.join(tmp_dir,'contacts.json')
		def self.contacts_file
			@@contacts_file
		end	
		@@status_file = File.join(tmp_dir,'status_info.json') 
		def self.status_file
			@@status_file
		end	
		@@inprogress_file = File.join(inbox,"#{Doc.filename_normalized}_IN_PROGRESS.txt")
		def self.inprogress_file
			@@inprogress_file
		end	
		@@errFile = File.join(project_dir, "ERROR_RUNNING_#{Doc.filename_normalized}.txt")
		def self.errFile
			@@errFile
		end	
	end
	class Resources
		@@thisscript = File.basename($0,'.rb')
		def self.thisscript
			@@thisscript
		end
	end	
	class Logs
		@@this_dir = File.expand_path(File.dirname(__FILE__))
		@@logfolder = File.join(AbsolutePaths.working_dir, 'logs')		#defaults for logging
		@@logfilename = "#{Doc.basename_normalized}_log.txt"	
		def self.log_setup(folder=@@logfolder,file=@@logfilename)		#can be overwritten in function call
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
end