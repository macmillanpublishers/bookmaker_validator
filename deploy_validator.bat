@echo off
rem strip out single quotes and extra periods from new files
Setlocal EnableDelayedExpansion
for %%a in (%1) do set init_fname=%%~nxa
for %%a in (%1) do set filepath=%%~dpa
set name_test=%init_fname:'=%
if "%name_test:~-4%" == ".doc" (
set basename=%name_test:~0,-4%
set ext=.doc)
if "%name_test:~-5%" == ".docx" (
set basename=%name_test:~0,-5%
set ext=.docx)
set basename=%basename:.=%
set "newname=%basename%%ext%"
if exist C:\staging.txt (set pathvar=bookmaker_validator_stg) else (set pathvar=bookmaker_validator)
set "logfile=C:\Users\padwoadmin\Dropbox (Macmillan Publishers)\bookmaker_logs\%pathvar%\std_out-err_logs\%basename%_bat_outerr.txt"
if NOT "%newname%" == "%init_fname%" (
(echo "bad characters in original filename, renaming file") >> "%logfile%"
ren %1 "%newname%"
set "infile=""%filepath%%newname%"""
set "infile=!infile:""="!"
) else (set infile=%1)

C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%infile%' >> "%logfile%" 2>&1
