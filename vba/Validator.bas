Attribute VB_Name = "Validator"
' =============================================================================
'     BOOKMAKER VALIDATOR
' =============================================================================
' By Erica Warren - erica.warren@macmillan.com
'
' ===== USE ===================================================================
' To validate/fix Word manuscripts automatically before createing egalleys.
'
' ===== DEPENDENCIES ==========================================================
' + !! PC ONLY !!!  Not testing anything on Mac.
' + Requires genUtils.dotm file in same dir, with LOCAL reference set to that
'   project (VBE > Tools > References > Browse).
' + Any declaration of a class in genUtils requires full project, i.e. `Dim
'   varName As genUtils.Dictionary`
' + Powershell script that calls this macro is looking for `Validator.Launch`
'   with parameters (1) FilePath and (2) LogPath.
' + ALL `MsgBox` called in ANY procedure MUST return correct default for this
'   macro to continue.


' ===== Global Declarations ===================================================
Option Explicit
' For error checking
Private Const strValidator As String = "Bookmaker.Validator."
' Create path for alert file in same dir as ACTIVE doc (NOT ThisDocument)
Private strAlertPath As String


' ===== Launch ================================================================
' Set up error checking, suppress alerts, check references before calling that
' project. Note: (1) ps1 script that calls this will (a) verify file is a Word
' doc, and (b) fix file name so it doesn't include spaces or special characters
' (2) Must handle ALL errors (write to ALERT file in same dir), (3) Must set
' `DisplayAlerts = False`, and be sure ALL msgbox return correct default.

Public Sub Launch(FilePath As String, Optional LogPath As String)

  ' Note, none of these will trap for compile errors!!
  On Error GoTo LaunchError   ' Suppresses run-time errors, passes to label
  Application.DisplayAlerts = wdAlertsNone  ' Only suppresses MsgBox function

  ' set global variable for path to write alert messages to, returns False if
  ' FilePath doesn't exist or point to a real file.
  If SetAlertPath(FilePath) = False Then
    Err.Raise 30001
  End If
  Debug.Print strAlertPath
  ' Verify genUtils.dotm is a reference. DO NOT CALL ANYTHING FROM `genUtils`
  ' IN THIS PROCEDURE! If ref is missing, will throw compile error.
  If IsRefMissing = True Then
    Err.Raise 30000
  End If

  
  
  
  
  
Cleanup:
  Application.DisplayAlerts = wdAlertsAll
  ' Only reset Error here, before completion.
  On Error GoTo 0
  Exit Sub

LaunchError:
  Err.Source = strValidator & "Launch"
  ' Have to assume here error may occur before we can access general error
  ' checker, so do everything in this module.
  Select Case Err.Number
    Case 30000
      Err.Description = "Reference missing"
    Case 30001
      Err.Description = "The string passed for the `FilePath` argument, " & _
        Chr(34) & FilePath & Chr(34) & ", does not point to a valid file."
  End Select
  ' Can't call primary error checker -- it's in the ref!
  ' Err object persists when new procedure is called, don't need to pass as arg
  Call WriteAlert
End Sub


' ===== CheckRef ==============================================================
' Checks if required projects are referenced and sets them, if possible. File
' must be in same dir as this project.

Private Function IsRefMissing() As Boolean
  On Error GoTo IsRefMissingError
  Dim strFileName As String
  Dim strPath As String
  Dim refs As References
  Dim ref As Reference

  IsRefMissing = False

  ' set references object
  Set refs = ThisDocument.VBProject.References

  ' Loop thru refs to check if broken
  For Each ref In refs
'      Debug.Print ref.Name
'      Debug.Print ref.FullPath
      ' Can't remove built-in refs
      If ref.IsBroken = True And ref.BuiltIn = False Then
        ' If it's a Project (i.e., VBA doc, not DLL)...
        If ref.Type = vbext_rk_Project Then
          ' ...get file name from end of orig. path, build new path ...
          strFileName = VBA.Right(ref.FullPath, InStr(StrReverse(ref.FullPath), _
            Application.PathSeparator))
'          strFileName = Application.PathSeparator & ref.Name & ".dotm"
          strPath = ThisDocument.Path & strFileName
          ' Now that we've gotten all info, remove ref
          refs.Remove ref
          ' If proj. file is not in same dir...
          If Dir(strPath) = vbNullString Then
            IsRefMissing = True
            ' Single missing ref means abort, so can stop loop
            Exit For
          Else
            ' file exists in same dir, so add new ref.
            refs.AddFromFile strPath
          End If
        End If
      End If
  Next ref
  
  Exit Function

IsRefMissingError:
  Err.Source = strValidator & "IsRefMissing"
  ' Can't call primary error checker -- it's in the ref!
  Call WriteAlert
End Function


' ===== SetAlertPath ==========================================================
' Set local path to write Alerts (i.e., unhandled errors). Must declare private
' global variable up top! On server, tries to write to same path as the file
' passed to Launch, if fails defaults to `validator_tmp`

Private Function SetAlertPath(origPath As String) As Boolean
  Dim strDir As String
  Dim strFile As String
  Dim lngSep As Long
  
  ' Validate file path. `Dir("")` returns first file in default Templates path
  ' so we have to check for null string AND file exists...
  If origPath <> vbNullString And Dir(origPath) <> vbNullString Then
    SetAlertPath = True
    ' Separate directory from file name
    lngSep = InStrRev(origPath, Application.PathSeparator)
    strDir = VBA.Left(origPath, lngSep)  ' includes trailing separator
    strFile = VBA.Right(origPath, Len(origPath) - lngSep)
    Debug.Print strDir & " | " & strFile
  
  ' If file DOESN'T exist, set defaults
  Else
    SetAlertPath = False
    Dim strLocalUser As String
    ' If we're on server, use validator default location
    strLocalUser = Environ("USERNAME")
    If strLocalUser = "padwoadmin" Then ' we're on the server
      strDir = "S:/validator_tmp/"
    ' If not, just use desktop
    Else
      strDir = Environ("USERPROFILE") & Application.PathSeparator & "Desktop" _
        & Application.PathSeparator
    End If
  End If
  
  ' build full alert file name
  strFile = "ALERT_" & strFile & "_" & Format(Date, "yyyy-mm-dd") & ".txt"
  
  ' combine path & file name!
  ' this is a global var that WriteAlert function can access directly.
  strAlertPath = strDir & strFile

End Function


' ===== WriteAlert ============================================================
' First intended as last resort if refs are missing, but maybe Err is always
' returned by ErrorChecker (or it's passed ByRef, so it's just updated), and
' we always write the Alert from the primary project. Then different projects
' can handle where to write alerts differently.

' Note `strAlertPath` is a private global variable that needs to be created
' before this is run.

Private Sub WriteAlert()
  ' Create log message
  Dim strAlert As String
  strAlert = "=========================================" & vbNewLine & _
    Now & " | " & Err.Source & vbNewLine & _
    Err.Number & ": " & Err.Description & vbNewLine

  ' Append message to log file
  Dim FileNum As Long
  FileNum = FreeFile()
  Open strAlertPath For Append As #FileNum
  Print #FileNum, strAlert
  Close #FileNum
  
  ' And now stop ALL code.
  End
End Sub


' ===== Main ==================================================================
' Once we know we've got the correct references set up, we can build our macro.

Private Function Main(bkmkrDoc As Document)
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
  
MainError:
  Err.Source = strValidator & "Launch"
  If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
    Resume
  Else
    Call genUtils.GeneralHelpers.GlobalCleanup
  End If
End Function

Sub ValidatorTest()
'' to simulate being called by ps1
  On Error GoTo TestError

  Call Validator.Launch("C:\Users\erica.warren\Desktop\validatortest.docx", "C:\Users\erica.warren\Desktop\validator-test.log")
  Exit Sub

TestError:
  Debug.Print Err.Number & ": " & Err.Description
End Sub
