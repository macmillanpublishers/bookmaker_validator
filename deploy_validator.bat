set "logfile=C:\Users\padwoadmin\Dropbox (Macmillan Publishers)\bookmaker_logs\bookmaker_validator\std_out-err_logs\%~n1_batch_outerr.txt"

C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%1' >> "%logfile%" 2>&1
