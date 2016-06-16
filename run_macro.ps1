#------------------------VARIABLES
param([string]$inputFile, [string]$macroName, [string]$logfile)
$filename=split-path $inputFile -Leaf			#file name without path
$filename_normalized=$filename -replace '[^a-zA-Z0-9-_.]',''
$filebasename=([io.fileinfo]$filename_normalized).basename
$fileext=([io.fileinfo]$filename_normalized).extension
$WorkingDir='S:\validator_tmp'
$tmpDir="$($WorkingDir)\$($filebasename)"
$working_file="$($tmpDir)\$($filename_normalized)"

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
LogWrite "$($TimestampA)      : run_macro -- macro: ""$($macroName)."" Received file ""$($working_file)"", checking filetype."

#--------------------- RUN THE MACRO
if ($fileext -eq ".doc" -Or $fileext -eq ".docx") {
	LogWrite "$($TimestampA)      : run_macro -- file is a ""$($fileext)"", commencing run Macro ""$($macroName)""..."
	cd $tmpDir
	$word = new-object -comobject word.application # create a com object interface (word application)
	$word.visible = $true
	$doc = $word.documents.open($working_file)
#	$word.run($macroName, [ref]$working_file, [ref]$logfile)	#this one for running via batch (deploy) script
	$word.run($macroName, $working_file, $logfile) 				#this one for calling direct from cmd line
	$doc.save()
	$doc.close()
	$word.quit()
	$TimestampB=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")   
	LogWrite "$($TimestampB)      : run_macro -- Macro ""$($macroName)"" completed, exiting .ps1"  
} else {
	LogWrite "$($TimestampA)      : run_macro -- file is a ""$($fileext)"", needs to be .doc or .docx , skipping Macro"
}

