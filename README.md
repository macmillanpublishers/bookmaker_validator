# bookmaker_validator
A workflow to take .doc(x) files via Dropbox, and run checks and auto-repairs on them.

# Dependencies
### Dropbox sdk gem:
The mailer requires the Dropbox sdk gem.  It can be installed like so:

`gem install dropbox-sdk`

### Folder Structure:

The validator repo should live here:
*S:\resources\bookmaker_scripts*

And a working dir should reside here:
*S:\validator_tmp*

### Output from Word macros:
The powershell passes the location of the logfile to a macro as the second argument
