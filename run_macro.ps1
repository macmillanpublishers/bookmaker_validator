#------------------------VARIABLES
param([string]$working_file, [string]$macroName, [string]$logfile)
$workfile_fixed=$working_file -replace '/','\'

##### Notes on running macros from server:
## the Template with the Macro needs to be in the Word Start folder on the server
## the macro project name should not be specified, but include module name: 'module.macro'

#-------------------- LOGGING
$TimestampA=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $logfile -value "$logstring"
}
LogWrite "$($TimestampA)      : run_macro -- macro: ""$($macroName)."" Received file ""$($workfile_fixed)"", checking filetype."

#--------------------- RUN THE MACRO
	$word = new-object -comobject word.application # create a com object interface (word application)
	$word.visible = $true
	$doc = $word.documents.open($workfile_fixed)
	$word.run($macroName, [ref]$workfile_fixed, [ref]$logfile)	#this one for running via batch (deploy) script
#	$word.run($macroName, $workfile_fixed, $logfile) 				#this one for calling direct from cmd line
	$doc.close([ref]$word.WdSaveOptions.wdDoNotSaveChanges)
	$word.quit()
  Start-Sleep 1
	$TimestampB=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")
	LogWrite "$($TimestampB)      : run_macro -- Macro ""$($macroName)"" completed, exiting .ps1"
