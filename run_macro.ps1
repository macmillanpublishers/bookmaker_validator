#------------------------VARIABLES
param([string]$working_file, [string]$macroName, [string]$logfile)

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
LogWrite "$($TimestampA)      : run_macro.ps1 -- macro: ""$($macroName)."" Received file ""$($working_file)"", checking filetype."

#--------------------- RUN THE MACRO
#if ($fileext -eq ".doc" -Or $fileext -eq ".docx") {
	LogWrite "$($TimestampA)      : run_macro.ps1 -- commencing run Macro ""$($macroName)""..."
	$word = new-object -comobject word.application # create a com object interface (word application)
	$word.visible = $true
	$doc = $word.documents.open($working_file)
	$word.run($macroName, [ref]$working_file, [ref]$logfile)	#these two for running via batch (deploy) script
	$doc.close([ref]$word.WdSaveOptions.wdDoNotSaveChanges)
	#$word.run($macroName, $working_file, $logfile) 				#these two for calling direct from cmd line
	#$doc.close($word.WdSaveOptions.wdDoNotSaveChanges)
	$word.quit()
  Start-Sleep 1
	$TimestampB=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")
	LogWrite "$($TimestampB)      : run_macro.ps1 -- Macro ""$($macroName)"" completed, exiting .ps1"
#} else {
	#LogWrite "$($TimestampA)      : run_macro -- file is a ""$($fileext)"", needs to be .doc or .docx , skipping Macro"
#}
