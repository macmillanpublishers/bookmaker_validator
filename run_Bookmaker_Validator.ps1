﻿#------------------------VARIABLES
param([string]$inputFile)
$filename=split-path $inputFile -Leaf			#file name without path
$filename_normalized=$filename.replace(' ','')
$filebasename=([io.fileinfo]$filename_normalized).basename
$fileext=([io.fileinfo]$filename_normalized).extension
$WorkingDir='S:\validator_tmp'
$tmpDir="$($WorkingDir)\$($filebasename)"
$working_file="$($tmpDir)\$($filename_normalized)"
#the Template with the Macro needs to be in the Word Start folder
#the macro project name should not be specified, but include module name: 'module.macro'
$macroName="Validator.Launch"

#-------------------- LOGGING
$TimestampA=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")   
$Logfolder="$($WorkingDir)\logs"
$Logfile="$($Logfolder)\$($filebasename)_log.txt"
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $Logfile -value "$logstring"
}
LogWrite "$($TimestampA)      : run_Bookmaker_Validator -- received file ""$($working_file)"", checking filetype."

#--------------------- RUN THE MACRO
if ($fileext -eq ".doc" -Or $fileext -eq ".docx") {
	LogWrite "$($TimestampA)      : run_Bookmaker_Validator -- file is a ""$($fileext)"", commencing run Macro ""$($macroName)""..."
	cd $tmpDir
	$word = new-object -comobject word.application # create a com object interface (word application)
	$word.visible = $false
	$doc = $word.documents.open($working_file)
	$word.run($macroName, [ref]$working_file, [ref]$Logfile)
	$doc.save()
	#if ($PSVersionTable.PSVersion.Major -gt 2) {
	#    $doc.saveas($working_file)
	#} else {
	#    $doc.saveas([ref]$working_file)
	#}
	$doc.close()
	$word.quit()
	$TimestampB=(Get-Date).tostring("yyyy-MM-dd hh:mm:ss")   
	LogWrite "$($TimestampB)      : run_Bookmaker_Validator -- Macro ""$($macroName)"" completed, exiting .ps1"  
}
Else {
	LogWrite "$($TimestampA)      : run_Bookmaker_Validator -- file is a ""$($fileext)"", needs to be .doc or .docx , skipping Macro"
}


