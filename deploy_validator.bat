@echo off
Setlocal EnableDelayedExpansion
set orig_fname=%1
set "new_name=%orig_fname:'=+++S+QUOTE+++%"
if NOT '%new_name%' == '%orig_fname%' (
echo "replacing apostrophes in name"
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%new_name%'
) else (
echo "no apostrophes in name, moving on"
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%1'
)
