@echo off
set logfile="S:\resources\logs\%~n1-stdout-and-err.txt"
if not exist "S:\resources\logs\processLogs" mkdir "S:\resources\logs\processLogs"
For /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
For /f "tokens=1-2 delims=/:" %%a in ("%TIME%") do (set mytime=%%a%%b)
set p_log="S:\resources\logs\processLogs\%~n1_%mydate%-%mytime%_validator.txt"
set p_log_tmp="S:\resources\logs\processLogs\%~n1_%mydate%-%mytime%_validatorTmp.txt"
if exist "S:\resources\logs\%~n1-stdout-and-err.txt" move "S:\resources\logs\%~n1-stdout-and-err.txt" "S:\resources\logs\past\%~n1-stdout-and-err_ARCHIVED_%mydate%-%mytime%.txt"

rem this is a block comment:  commenting lines 11-20, line 25, 29- separate processwatch and mailer scripts may need to be setup
goto comment
rem write scriptnames to file for ProcessLogger to rm on success:
(
  echo validator_tmparchive
  echo run_Bookmaker_Validator
  echo validator_mailer   
  echo validator_cleanup
  echo mail-alert
	
) >%p_log%
:comment

@echo on
@echo %date% %time% >> %logfile% 2>&1s

rem /b PowerShell -NoProfile -ExecutionPolicy Bypass -Command "S:\resources\bookmaker_scripts\utilities\processwatch.ps1 %p_log% '%1'"
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\validator_tmparchive.rb '%1' >> %logfile% 2>&1 && call :ProcessLogger validator_tmparchive
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "S:\resources\bookmaker_scripts\bookmaker_validator\run_Bookmaker_Validator.ps1 '%1'" && call :ProcessLogger run_Bookmaker_Validator
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\validator_mailer.rb '%1' >> %logfile% 2>&1 && call :ProcessLogger validator_mailer
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\validator_cleanup.rb '%1' >> %logfile% 2>&1 && call :ProcessLogger validator_cleanup
rem PowerShell -NoProfile -ExecutionPolicy Bypass -Command "S:\resources\bookmaker_scripts\utilities\mail-alert.ps1 '%1'" && call :ProcessLogger mail-alert


goto:eof
rem ************  Function *************
:ProcessLogger
set input=%1
findstr /v %1 %p_log% > %p_log_tmp%
move /Y %p_log_tmp% %p_log%
goto :eof
