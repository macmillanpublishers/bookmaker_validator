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
' For error checking:
Private Const strValidator As String = "Bookmaker.Validator."
' Create path for alert file in same dir as ACTIVE doc (NOT ThisDocument)
Private strAlertPath As String
' Store style check pass/fail values in this json
Private strJsonPath As String
' Ditto but for log file
Private strLogPath As String

Private StartTime As Double


' ===== Enumerations ==========================================================
Public Enum ValidatorError
  err_ValErrGeneral = 30000
  err_TestsFailed = 30001
  err_RefMissing = 30002
  err_PathInvalid = 30003
  err_NoPassKey = 30004
End Enum


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
  If SetOutputPaths(FilePath, LogPath) = False Then
    Err.Raise err_PathInvalid
  End If
  
  ' ditto all that for LogPath

  ' Verify genUtils.dotm is a reference. DO NOT CALL ANYTHING FROM `genUtils`
  ' IN THIS PROCEDURE! If ref is missing, will throw compile error.
  If IsRefMissing = True Then
    Err.Raise err_RefMissing
  End If
  
' ===================================================
' Once we're certain genUtils is available, pass to Main validator procedure
' and use that function for handling errors.
' ===================================================
  Call Main(FilePath)
  Call ValidatorCleanup
  
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
    Case err_RefMissing
      Err.Description = "VBA reference missing."
    Case err_PathInvalid
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
' passed to Launch, if fails defaults to `validator_tmp`.

' Also setting path to `style_check.json here, since in same dir.

Private Function SetOutputPaths(origPath As String, origLogPath As String) As _
  Boolean
  Dim strDir As String
  Dim strFile As String
  Dim lngSep As Long
  
  ' Don't use genUtils.IsItThere because we haven't checked refs yet.
  ' Validate file path. `Dir("")` returns first file or dir in default Templates
  ' dir so we have to check for null string AND if file exists...
  If origPath <> vbNullString And Dir(origPath) <> vbNullString Then
    ' File exists (thus, directory exists too)
    SetOutputPaths = True
    ' Separate directory from file name
    lngSep = InStrRev(origPath, Application.PathSeparator)
    strDir = VBA.Left(origPath, lngSep)  ' includes trailing separator
    strFile = VBA.Right(origPath, Len(origPath) - lngSep)
'    Debug.Print strDir & " | " & strFile
  
  ' If file DOESN'T exist, set defaults
  Else
    SetOutputPaths = False
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
'  Debug.Print strFile
  
  ' combine path & file name!
  ' this is a global var that WriteAlert function can access directly.
  strAlertPath = strDir & strFile
'  Debug.Print strAlertPath

  ' ditto global var for style check file
  strJsonPath = strDir & "style_check.json"
  ' Also verify log file. Could add more error handling later but for now
  ' just trusting that will be created by calling .ps1 script
  strLogPath = origLogPath

End Function


' ===== WriteAlert ============================================================
' First intended as last resort if refs are missing, but maybe Err is always
' returned by ErrorChecker (or it's passed ByRef, so it's just updated), and
' we always write the Alert from the primary project. Then different projects
' can handle where to write alerts differently.

' Note `strAlertPath` is a private global variable that needs to be created
' before this is run.

Private Sub WriteAlert(Optional blnEnd As Boolean = True)
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
  
  ' Optional: stops ALL code.
  If blnEnd = True Then
    End
  End If
End Sub

' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
'     PROCEDURES BELOW CAN REFERENCE `genUtils`
' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

' ===== Main ==================================================================
' Once we know we've got the correct references set up, we can build our macro.
' DocPath exists and is a Word file already validated.

Private Function Main(DocPath As String) As Boolean
  On Error GoTo MainError
  ' Set up variables to store test results
  Dim strKey As String
  Dim blnPass As Boolean
  Dim dictTests As genUtils.Dictionary
  
' NOTE! Each procedure called returns a dictionary with results of various
' tests. Each will include a "pass" key--a value of "False" means that the
' validator should NOT continue (checked in `ReturnDict` sub.
  
' ----- INITIALIZE ------------------------------------------------------------
  strKey = "initialize"
  Set dictTests = genUtils.Reports.ReportsStartup(DocPath)
  Call ReturnDict(strKey, dictTests)

' *****************************************************************************
'       ALWAYS CHECK STYLES
' *****************************************************************************
' ----- OVERALL STYLE CHECKS --------------------------------------------------
  strKey = "styled"
  Set dictTests = genUtils.Reports.StyleCheck()
  Call ReturnDict(strKey, dictTests)
  

' *****************************************************************************
'       CONTINUE IF MS IS STYLED
' *****************************************************************************

' ----- ISBN VALIDATION -------------------------------------------------------
  strKey = "isbn"
  Set dictTests = genUtils.Reports.IsbnCheck
  Call ReturnDict(strKey, dictTests)

' ----- TITLEPAGE VALIDATION --------------------------------------------------
  strKey = "titlepage"
  Set dictTests = genUtils.Reports.TitlepageCheck
  Call ReturnDict(strKey, dictTests)

' ----- SECTION TAGGING -------------------------------------------------------
  strKey = "sections"
  Set dictTests = genUtils.Reports.SectionCheck
  Call ReturnDict(strKey, dictTests)
  
' ----- HEADING VALIDATION ----------------------------------------------------
  strKey = "headings"
  Set dictTests = genUtils.Reports.HeadingCheck
  Call ReturnDict(strKey, dictTests)
  
' ----- ILLUSTRATION VALIDATION -----------------------------------------------
  strKey = "illustrations"
  Set dictTests = genUtils.Reports.IllustrationCheck
  Call ReturnDict(strKey, dictTests)

' ----- RUN CLEANUP MACRO -----------------------------------------------------
' To do: convert to function that returns dictionary of test results
  
  
' ----- RUN CHAR STYLES MACRO -------------------------------------------------
' To do: convert to function that returns dictionary of test results
  
  
  Set dictTests = Nothing
  
  Main = True
  Exit Function
MainError:
  Err.Source = strValidator & "Main"
  Select Case Err.Number
    Case ValidatorError.err_TestsFailed
      Err.Description = "The test dictionary for `" & strKey & "` returned empty."
      Call ValidatorCleanup
    Case ValidatorError.err_NoPassKey
      Err.Description = strKey & " dictionary has no `pass` key."
      Call ValidatorCleanup
    Case Else
      If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
        Resume
      Else
        Call ValidatorCleanup
      End If
  End Select
End Function


' ===== ValidatorCleanup ======================================================
' Always run last. In fact, it ends ALL macro execution so by definition it'll
' be last! If Err object is not 0, will write an ALERT. Only call AFTER you
' know we've set the `strAlertPath` and `strLogPath` variables.

Public Sub ValidatorCleanup()
  ' I don't love this, but adding `On Error` statement to cancel previous,
  ' at least we'll be sure the macro ends and doesn't get sent in a loop.
  
  ' What if one of the procedures we are calling fails?
' Actually CAN'T set On Error here: it clears the Err object!
' And we need WriteAlert to read that, if there is one.

  Dim blnResult As Boolean
  Dim saveValue As WdSaveOptions
  If Err.Number = 0 Then
    blnResult = True
    saveValue = wdSaveChanges
  Else
    blnResult = False
    saveValue = wdDoNotSaveChanges
    Call WriteAlert(False)
  End If
  
  On Error GoTo ValidatorCleanupError
  ' Close all open documents
  Dim objDoc As Document
  Dim strExt As String
  For Each objDoc In Documents
    ' don't close any macro templates, might be running code.
    strExt = VBA.Right(objDoc.Name, InStr(StrReverse(objDoc.Name), "."))
    If strExt <> ".dotm" Then
      objDoc.Close saveValue
    End If
  Next objDoc
  
  ' Write our final element to `style_check.json` file
  Call genUtils.AddToJson(strJsonPath, "completed", blnResult)
  
  ' Write log entry from JSON values
  ' Should always be there (see previous line)
  If genUtils.IsItThere(strJsonPath) = True Then
    Call JsonToLog
  End If

' DON'T `Exit Sub` before this - we want it to `End` no matter what.
ValidatorCleanupError:
' ============================================================================
' ----------------------Timer End-------------------------------------------

  Dim SecondsElapsed As Double
' Determine how many seconds code took to run
  SecondsElapsed = Round(Timer - StartTime, 2)
    
' Notify user in seconds
  Debug.Print "This code ran successfully in " & SecondsElapsed & " seconds"
' ============================================================================

  End   ' Stops ALL code execution.
End Sub


' ===== JsonToLog =============================================================
' Converts `style_check.json` to human-readable log entry, and writes to log.

Public Sub JsonToLog()
  On Error GoTo JsonToLogError
  Dim jsonDict As genUtils.Dictionary
  Set jsonDict = genUtils.ReadJson(strJsonPath)
  
  Dim strLog As String  ' string to write to log
' Following Matt's formatting for other scripts
  strLog = Format(Now, "yyyy-mm-dd hh:mm:ss AMPM") & "   : " & strValidator _
    & "Launch -- results:" & vbNewLine
    
  Dim strSpaces As String
' To get logs to line up nicely, haha
  strSpaces = VBA.Space(27)
  
' Loop through `style_check.json` and write to log. Can add more detailed info
' in the future.

' Also don't stress now, but in future could write more generic dict-to-json
' function by breaking into multiple functions that call each other:
' Value is an array (return all items in comma-delineated string - REDUCE!)
' Value is an object (call this function again!)
' Value is neither (thus, number, string, boolean) - just write to string.
  Dim strKey1 As Variant
  Dim strKey2 As Variant
  Dim arrValues() As Variant
  Dim A As Long
  
' Anyway, loop through json data and build string to write to log
  With jsonDict
    For Each strKey1 In .Keys
    ' Value may be another dictionary/object
      If VBA.IsObject(.Item(strKey1)) = True Then
      ' loop through THIS dictionary
        For Each strKey2 In .Item(strKey1).Keys
          Debug.Print .Item(strKey1).Item(strKey2)
          strLog = strLog & strSpaces & strKey1 & ": " & strKey2 & ": " & _
            .Item(strKey1).Item(strKey2)
          Debug.Print strLog
        ' Value here might be an array
          If VBA.IsArray(.Item(strKey1).Item(strKey2)) = True Then
            arrValues = .Item(strKey1).Item(strKey2)
            ' Loop through array, write values
              For A = LBound(arrValues) To UBound(arrValues)
                If A <> LBound(arrValues) Then
                  ' add comma and space between values
                  strLog = strLog & ", "
                End If
                strLog = strLog & arrValues(A)
              Next A

          Else
          ' Pretty sure it's something we can convert to string directly
            strLog = strLog & .Item(strKey2)
          End If
          strLog = strLog & vbNewLine
        Next strKey2
      Else
        strLog = strLog & strSpaces & strKey1 & ": " & .Item(strKey1) & vbNewLine
      End If
    Next strKey1
  End With
  
  Debug.Print strLog
  
' Write string to log file, which should have been set earlier!
  Call genUtils.AppendTextFile(strLogPath, strLog)
  
  Exit Sub

JsonToLogError:
  Err.Source = strValidator & "JsonToLog"
  Call WriteAlert(blnEnd:=True)
  
End Sub


' ===== ReturnDict ============================================================
' Process dictionary returned from reports section

Private Sub ReturnDict(SectionKey As String, TestDict As genUtils.Dictionary)
  On Error GoTo ReturnDictError
  If TestDict Is Nothing Then
    Err.Raise ValidatorError.err_TestsFailed
  Else
    If TestDict.Exists("pass") = True Then
      ' write tests to JSON file
      Call genUtils.AddToJson(strJsonPath, SectionKey, TestDict)
      If TestDict("pass") = False Then
        Call ValidatorCleanup
      End If
    Else
      Err.Raise ValidatorError.err_NoPassKey
    End If
  End If
  Exit Sub
  
ReturnDictError:
  Err.Source = strValidator & "ReturnDict"
  Select Case Err.Number
    Case ValidatorError.err_TestsFailed
      Err.Description = "The test dictionary for `" & SectionKey & "` returned empty."
      Call ValidatorCleanup
    Case ValidatorError.err_NoPassKey
      Err.Description = strKey & " dictionary has no `pass` key."
      Call ValidatorCleanup
    Case Else
      If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
        Resume
      Else
        Call ValidatorCleanup
      End If
  End Select

End Sub

Sub ValidatorTest()
'' to simulate being called by ps1
  On Error GoTo TestError

' =================================================
' Timer Start
                                  
' Remember time when macro starts
  StartTime = Timer
' =================================================

  Call Validator.Launch("C:\Users\erica.warren\Desktop\validator-test.docx", "C:\Users\erica.warren\Desktop\validator-test.log")
  
  Exit Sub

TestError:
  Debug.Print Err.Number & ": " & Err.Description
End Sub
