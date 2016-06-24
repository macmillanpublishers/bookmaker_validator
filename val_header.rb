require 'fileutils'

require_relative 'utilities/mcmlln-tools.rb'

module Vldtr
	class Project
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
		@@project_dir = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].join(File::SEPARATOR)
		def self.project_dir
			@@project_dir
		end
		@@project_name = input_file.split(Regexp.union(*[File::SEPARATOR, File::ALT_SEPARATOR].compact))[0...-2].pop
		def self.project_name
			@@project_name
		end		
	end

#working my way from the top, I am up to here, for paths:
inbox = File.join(project_dir, 'IN')
outbox = File.join(project_dir, 'OUT')
working_dir = File.join('S:', 'validator_tmp')
tmp_dir=File.join(working_dir, basename_normalized)
validator_dir = File.dirname(__FILE__)
mailer_dir = File.join(validator_dir,'mailer_messages')
working_file = File.join(tmp_dir, filename_normalized)
bookinfo_file = File.join(tmp_dir,'book_info.json')
stylecheck_file = File.join(tmp_dir,'style_check.json')
contacts_file = File.join(tmp_dir,'contacts.json')
status_file = File.join(tmp_dir,'status_info.json') 
testing_value_file = File.join("C:", "staging.txt")
#inprogress_file = File.join(inbox,"#{filename_normalized}_IN_PROGRESS.txt")
errFile = File.join(project_dir, "ERROR_RUNNING_#{filename_normalized}.txt")


  class Paths
	    def self.tmp_dir
	      $tmp_dir
	    end

	    def self.log_dir
	      $log_dir
	    end

	    def self.scripts_dir
	      $scripts_dir
	    end

	    def self.resource_dir
	      $resource_dir
	    end

	    # The location where each bookmaker component lives.
		@@core_dir = File.join(scripts_dir, "bookmaker", "core")
		def self.core_dir
			@@core_dir
		end

		# Path to the submitted_assets directory
		def self.submitted_images
			if $assets_dir
				$assets_dir
			else 
				Project.input_dir
			end
		end

		# Path to the temporary working directory
		@@project_tmp_dir = File.join(tmp_dir, Project.filename)
		def self.project_tmp_dir
			@@project_tmp_dir
		end

		# Path to the images subdirectory of the temporary working directory
		@@project_tmp_dir_img = File.join(project_tmp_dir, "images")
		def self.project_tmp_dir_img
			@@project_tmp_dir_img
		end
		
		# Full path to outputtmp.html file
		@@outputtmp_html = File.join(project_tmp_dir, "outputtmp.html")
		def self.outputtmp_html
			@@outputtmp_html
		end

		# Full path and filename for the normalized (i.e., spaces removed) input file in the temporary working dir
		@@project_tmp_file = File.join(project_tmp_dir, Project.filename_normalized)
		def self.project_tmp_file
			@@project_tmp_file
		end
		
		# Full path and filename for the .docx file
		@@project_docx_file = File.join(project_tmp_dir, "#{Project.filename}.docx")
		def self.project_docx_file
			@@project_docx_file
		end

		# Full path and filename for the "in use" alert that is created
		@@alert = File.join(Project.working_dir, "IN_USE_PLEASE_WAIT.txt")
		def self.alert
			@@alert
		end

		# Full path and filename for the "done" directory in Project working directory
		def self.done_dir
			if $done_dir
				$done_dir
			else 
				Project.input_dir
			end
		end

		# Full path to project log file
		@@log_file = File.join(log_dir, "#{Project.filename}.txt")
		def self.log_file
			@@log_file
		end
	end
end