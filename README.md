# bookmaker_validator
bookmaker_validator accepts .doc(x) files via Dropbox, and then runs checks and auto-repairs them via Word Macro(s).

# Dependencies
#### Dropbox-sdk, Process, nokogiri gems:
The mailer requires the python sdk for dropbox api, and the process watcher requires the process gem.  They can be installed like so:

`pip install dropbox`
`gem install process`

If you encounter errors using pip to install python dropbox sdk, see the repo for instructions on installing from source: https://github.com/dropbox/dropbox-sdk-python

The *nokogiri* gem is also required, but installation varies by platform.
Go [here](http://www.nokogiri.org/tutorials/installing_nokogiri.html) for instructions.


#### Word .dotm file with Macro
The Word .dotm file needs to be loaded in Word's Startup folder, and the 'run_Bookmaker_Validator.ps1' script is expecting it to have a module named 'Validator' and macro named 'Launch'

The 'Launch' macro is passed two arguments:
* arg1 is the input file.
* arg2 is the logfile for stdout

#### Folder Structure:
The validator repo should live here:
*S:\resources\bookmaker_scripts*

And a working dir should reside here:
*S:\validator_tmp*


# Stdout & errors
#### Stdout
Informational logs from all scripts and the macro are piped into a logfile for each file (subsequent runs for the same .doc are appended).
These reside in a Dropbox logfolder: *Dropbox (Macmillan\ Publishers)/bookmaker_logs/egalleymaker/logs*

#### Stderr
* Error output from *macros* is expected in the same dir as the target file (the file the macros are running on).
Any extraneous files in the tmpdir ending in .json, .txt or .log will be handled as errors by the mailer and cleanup scripts, and the whole tmpdir moved to the aforementioned logfolder for review.

Errors and output from the process watcher &/or deploy.rb files are logged to *Dropbox (Macmillan\ Publishers)/bookmaker_logs/egalleymaker/std_out-err_logs*
