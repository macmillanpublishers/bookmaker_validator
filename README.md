# bookmaker_validator
bookmaker_validator accepts .doc(x) files via Dropbox, and then runs checks and auto-repairs on them via Word Macro(s).

# Dependencies
#### Dropbox sdk gem:
The mailer requires the Dropbox sdk gem.  It can be installed like so:

`gem install dropbox-sdk`

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
* Error output from *macros* is expected dropped in the same dir as the target file (the one macros are being run upon).
Any extraneous files in the tmpdir ending in .json, .txt or .log will be handled as errors by the mailer and cleanup scripts, and moved to *S:\validator_tmp\logs* for review.

* Caught errors are piped to the same logfile as stdout.  Fatal & uncaught errors from the .rb & .ps1 scripts are logged to *S:\resources\logs* via the .bat.
