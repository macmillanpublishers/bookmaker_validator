Attribute VB_Name = "Validator"
Option Explicit
' For error checking
Private Const strValidator As String = "Bookmaker.Validator."

Public Sub Launch(FilePath As String, Optional LogPath As String)
' 1. Check that passed file is a Word doc (see SharedMacros)
' 2. Handle ALL errors -- write to ERROR file in same dir
' 3. set DisplayAlerts=False, be sure all msgbox return correct default

  ' ---------------------------------------------------------------------------
  '   ERROR CHECKING, ALERTS, OTHER SETUP
  ' ---------------------------------------------------------------------------
  On Error GoTo LaunchError
  Application.DisplayAlerts = wdAlertsNone    ' Does not suppress run-time errors
  
  ' The .ps1 that calls this macro also opens the file, so should already be
  ' part of the Documents collection, but we'll check anyway.
  If genUtils.GeneralHelpers.IsOpen(FilePath) = False Then
    Documents.Open (FilePath)
  End If

  ' create reference to our document
  Dim docActive As Document
  Set docActive = Documents(FilePath)
  
  ' create dictionary of style information
  Dim dictStyles As genUtils.Dictionary
  Set dictStyles = genUtils.Reports.StyleDictionary(docActive)
  
  Debug.Print dictStyles.Count
  Debug.Print dictStyles("styled").Count
  Debug.Print dictStyles("unstyled").Count
  
  
  
  
Cleanup:
  Application.DisplayAlerts = wdAlertsAll
  On Error GoTo 0
  Exit Sub

LaunchError:
  Err.Source = strValidator & "Launch"
  If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
    Resume
  Else
    Call genUtils.GeneralHelpers.GlobalCleanup
  End If
End Sub

Sub ValidatorTest()
'' to simulate being called by ps1

  Call Validator.Launch("C:\Users\erica.warren\Desktop\validator-test.docx", "C:\Users\erica.warren\Desktop\validator-test.log")
End Sub
