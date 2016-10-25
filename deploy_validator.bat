@echo off
Setlocal DisableDelayedExpansion
set "orig_fname=%~1"
set "new_name=%orig_fname:!=+++EXCLM+++%"
Setlocal EnableDelayedExpansion
set "new_name=!new_name:'=+++S+QUOTE+++!"
if NOT '!new_name!' == '!orig_fname!' (
echo "replacing single quotes and-or exclamations in name"
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '!new_name!'
) else (
echo "no single quotes or exclamations in name, moving on"
C:\Ruby200\bin\ruby.exe S:\resources\bookmaker_scripts\bookmaker_validator\deploy_validator.rb '%1'
)
