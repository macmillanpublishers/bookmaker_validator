# this .ps1 script is a simplification of htmlmaker_preprocessing.ps1
# it just expects a .doc file as a parameter and saves it as a .docx
# optional removal of the .doc
# no built-in logging; that can be more easily captured with open3 or similar whatever invokes this

param([string]$inputFile)
$docpath = "$($inputFile)x"

$word = New-Object -ComObject word.application
$word.visible = $true

# Make sure "Store random number..." setting is off
$word.Options.StoreRSIDOnSave = $false
Write-Host "Removing revision data"

$doc = $word.documents.open($inputFile)

# turn off track changes, accept all changes and delete all comments
# have to do here, or we don't solve dumb XML revision problem
$doc.TrackRevisions = $false
$doc.Revisions.AcceptAll()
Foreach($comment in $doc.Comments)
{
    $comment.Delete()
}

# save file as .docx
# If we didn't make changes we still need to force save, so we can
# remove any revision data in XML file, so set 'Saved' property to false
$doc.Saved=$false
$wdFormatDocx = 16  # wdFormatDocumentDefault is docx, reference number is 16

# Have to add [ref]s for certain versions of powershell (2.0),
# we'll see which way works on server
# https://richardspowershellblog.wordpress.com/2012/10/15/powershell-3-and-word/
# so only use one or the other of these next two lines
$saved=$doc.Saved
#$doc.saveas($docpath, $wdFormatDocx)
$doc.saveas([ref]$docpath, [ref]$wdFormatDocx)

$doc.close()
$word.Quit()
$word = $null

# Next line if you want to remove the original .doc file
Remove-Item ($inputFile)

[gc]::collect()
[gc]::WaitForPendingFinalizers()
