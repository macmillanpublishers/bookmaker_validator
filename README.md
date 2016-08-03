# bookmaker_validator
bookmaker_validator accepts .doc(x) files via Dropbox, and then runs checks and auto-repairs them via Word Macro(s).

# Dependencies
#### Dropbox sdk gem, Process gem:
The mailer requires the Dropbox sdk gem, and the process watcher requires the process gem.  They can be installed like so:

`gem install dropbox-sdk`
`gem install process`

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
Informational logs from all scripts and the macro are piped into the existing logfile for a given file, in *S:\validator_tmp\logs*

#### Stderr
* Error output from *macros* is expected in the same dir as the target file (the file the macros are running on).
Any extraneous files in the tmpdir ending in .json, .txt or .log will be handled as errors by the mailer and cleanup scripts, and the whole tmpdir moved to *S:\validator_tmp\logs* for review.

* Caught errors are piped to the same logfile as stdout.  Fatal & uncaught errors from the .rb & .ps1 scripts are logged to *S:\resources\logs\* via the .Deploy.rb script.

Errors and output from the process watcher are logged to *S:\resources\logs\*
