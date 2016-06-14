set logfile="S:\resources\logs\%~n1-stdout-and-err.txt"

C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%1' >> %logfile% 2>&1