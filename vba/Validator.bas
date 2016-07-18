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
Private lngCleanupCount As Long
' Create path for alert file in same dir as ACTIVE doc (NOT ThisDocument)
Private strAlertPath As String
' Store style check pass/fail values in this json
Private strJsonPath As String
' Ditto but for log file
Private strLogPath As String
' Name of originally called procedure, to write to logs
Private strProcName As String

Private StartTime As Double
Private SecondsElapsed As Double


' ===== Enumerations ==========================================================
Public Enum ValidatorError
  err_ValErrGeneral = 30000
  err_TestsFailed = 30001
  err_RefMissing = 30002
  err_PathInvalid = 30003
  err_NoPassKey = 30004
  err_StartupFail = 30005
  err_ValidatorMainFail = 30006
  err_IsbnMainFail = 30007
End Enum

' ===== IsbnSearch ============================================================
' Searches doc for ISBN, called from Powershell.

' PUBLIC because needs to be called independently from powershell if file name
' doesn't include ISBN. Optional FilePath is for passing doc path from PS.

Public Function IsbnSearch(FilePath As String, Optional LogFile As String) _
  As String
  On Error GoTo IsbnSearchError
  strProcName = strValidator & "IsbnSearch"
  
' Startup checks for references, etc.
  If ValidatorStartup(FilePath, LogFile) = False Then
    Err.Raise ValidatorError.err_StartupFail
  End If

' Main procedure, assumes ref to genUtils project intact
  Dim strIsbn As String
  strIsbn = IsbnMain(FilePath)

'' Returned false doesn't necessarily mean a problem happened. Maybe just didn't
'' find anything:
'  If strIsbn = vbNullString Then
'    Err.Raise ValidatorError.err_IsbnMainFail
'  End If
  
  IsbnSearch = strIsbn

' Various cleanup stuff, including `End` all code execution.
  Call ValidatorExit(RunCleanup:=True, EndMacro:=False)
  
  Exit Function

IsbnSearchError:
  Err.Source = strValidator & "IsbnSearch"
  Select Case Err.Number
    Case ValidatorError.err_StartupFail
      Err.Description = strValidator & "ValidatorStartup failed to complete."
    Case ValidatorError.err_IsbnMainFail
      Err.Description = strValidator & "IsbnMain failed to complete."
  End Select
  Call ValidatorExit(RunCleanup:=False)
End Function


' ===== Launch ================================================================
' Set up error checking, suppress alerts, check references before calling that
' project. Note: (1) ps1 script that calls this will (a) verify file is a Word
' doc, and (b) fix file name so it doesn't include spaces or special characters
' (2) Must handle ALL errors (write to ALERT file in same dir), (3) Must set
' `DisplayAlerts = False`, and be sure ALL msgbox return correct default.

Public Sub Launch(FilePath As String, Optional LogPath As String)
  On Error GoTo LaunchError
  strProcName = strValidator & "Launch"
' Startup checks for references, etc.
  If ValidatorStartup(FilePath, LogPath) = False Then
    Err.Raise ValidatorError.err_StartupFail
  End If

' Main procedure, assumes ref to genUtils project intact
  If ValidatorMain(FilePath) = True Then
    SecondsElapsed = Round(Timer - StartTime, 2)
    Debug.Print "`Main` function complete: " & SecondsElapsed
  Else
    Err.Raise ValidatorError.err_ValidatorMainFail
  End If

' Various cleanup stuff, including `End` all code execution.
  Call ValidatorExit(RunCleanup:=True)
  
  Exit Sub

LaunchError:
  Err.Source = strValidator & "Launch"
  Select Case Err.Number
    Case ValidatorError.err_StartupFail
      Err.Description = strValidator & "ValidatorStartup failed to complete."
    Case ValidatorError.err_ValidatorMainFail
      Err.Description = strValidator & "ValidatorMain failed to complete."
  End Select
  Call ValidatorExit(RunCleanup:=False)
End Sub

' ===== ValidatorStartup ======================================================
' Checks and such to run before we can call anything in genUtils project. File
' and log paths by ref because we might change them.

Private Function ValidatorStartup(ByRef StartupFilePath As String, ByRef _
  StartupLogPath As String) As Boolean
  On Error GoTo ValidatorStartupError
  ValidatorStartup = False
  StartTime = Timer
  Application.DisplayAlerts = wdAlertsNone
'  Application.ScreenUpdating = False

' Fix path separators in file path names
  Dim strFilePath As String
  Dim strLogPath As String
  strFilePath = FilePathCleanup(StartupFilePath)
  strLogPath = FilePathCleanup(StartupLogPath)
  
' set global variable for path to write alert messages to, returns False if
' FilePath doesn't exist or point to a real file.
  If SetOutputPaths(strFilePath, strLogPath) = False Then
    Err.Raise err_PathInvalid
  End If
  SecondsElapsed = Round(Timer - StartTime, 2)
  Debug.Print "Output paths set: " & SecondsElapsed

' Verify genUtils.dotm is a reference. DO NOT CALL ANYTHING FROM `genUtils`
' IN THIS PROCEDURE! If ref is missing, will throw compile error.
  If IsRefMissing = True Then
    Err.Raise err_RefMissing
  End If

  SecondsElapsed = Round(Timer - StartTime, 2)
  Debug.Print "References OK: " & SecondsElapsed
  ValidatorStartup = True
  Exit Function
  
ValidatorStartupError:
  Err.Source = strValidator & "ValidatorStartup"
' Have to assume here error may occur before we can access general error
' checker, so do everything in this module.
  Select Case Err.Number
    Case err_RefMissing
      Err.Description = "VBA reference missing."
    Case err_PathInvalid
      Err.Description = "The string passed for the `FilePath` argument, " & _
        Chr(34) & StartupFilePath & Chr(34) & ", does not point to a valid file."
  End Select
  Call ValidatorExit(RunCleanup:=False)
End Function

' ===== ValidatorExit ======================================================
' Always run last. In fact, it ends ALL macro execution so by definition it'll
' be last! If Err object is not 0, will write an ALERT. `RunCleanup` param
' should be set to False if called from a procedure that runs before we
' have checked if refs are set. `EndMacro` should be set to False if you
' want code execution to return to the calling procedure.

Public Sub ValidatorExit(Optional RunCleanup As Boolean = True, Optional _
  EndMacro As Boolean = True)
' Global variable counter in case error throw before we reset On Error
' More than 1 is an error, but letting it run a few times to capture more data
  lngCleanupCount = lngCleanupCount + 1
  Debug.Print "ValidatorExit: " & lngCleanupCount
  If lngCleanupCount > 3 Then GoTo ValidatorExitError

' NOTE!! Must get Err object values before setting new On Error statement
' Did macro complete correctly?
  Dim blnCompleted As Boolean
  If Err.Number = 0 Then
    blnCompleted = True
  Else
    blnCompleted = False
    Call WriteAlert(False)
  End If

' Now we can reset On Error (which includes Err.Clear)
  On Error GoTo ValidatorExitError
  
' Do we know if doc is styled?
  Dim blnStyled As Boolean
  If RunCleanup = True Then
    blnStyled = ValidatorCleanup(blnCompleted)
    Call JsonToLog
  Else
    blnStyled = False
  End If

' Only save doc if macro completed w/o error AND correctly styled
  Dim saveValue As WdSaveOptions
  If blnCompleted = True And blnStyled = True Then
    saveValue = wdSaveChanges
  Else
    saveValue = wdDoNotSaveChanges
  End If
  
' Close all open documents
  Dim objDoc As Document
  Dim strExt As String
  For Each objDoc In Documents
  ' don't close any templates, might be running code.
    strExt = VBA.Right(objDoc.Name, InStr(StrReverse(objDoc.Name), "."))
    If strExt <> ".dotm" Then
      objDoc.Close saveValue
    End If
  Next objDoc
  
' DON'T `Exit Sub` before this - we want it to `End` no matter what.
ValidatorExitError:
  If Err.Number <> 0 Then
    Err.Source = strValidator & "ValidatorExit"
    Call WriteAlert(False)
  End If
  
  Application.DisplayAlerts = wdAlertsAll
  Application.ScreenUpdating = True
  Application.ScreenRefresh

' Timer End
  SecondsElapsed = Round(Timer - StartTime, 2)
  Debug.Print "This code ran successfully in " & SecondsElapsed & " seconds"

  If EndMacro = True Then
    On Error GoTo 0
  ' Stops ALL code execution (might be called to cleanup after error).
    End
  End If
End Sub

' ===== FilePathCleanup =======================================================
' Ensures path separators are correct for a file path or directory. Do not use
' genUtils procedures, need to check this before checking references. At some
' point figure out how to include OSX paths?

Private Function FilePathCleanup(ByRef FullFilePath As String) As String
  On Error GoTo FilePathCleanupError
  Dim strReturn As String
  strReturn = FullFilePath
  If InStr(strReturn, "/") > 0 Then
    strReturn = VBA.Replace(strReturn, "/", Application.PathSeparator)
  End If
'  Debug.Print strReturn
  FilePathCleanup = strReturn
  Exit Function
  
FilePathCleanupError:
  Err.Source = strValidator & "FilePathCleanup"
  Call ValidatorExit(RunCleanup:=False)
End Function

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
  Call ValidatorExit(RunCleanup:=False)
End Function


' ===== SetOutputPaths ========================================================
' Set local path to write Alerts (i.e., unhandled errors). Must declare private
' global variable up top! On server, tries to write to same path as the file
' passed to Launch, if fails defaults to `validator_tmp`.

' Also setting path to style_check.json here, since in same dir.

Private Function SetOutputPaths(origPath As String, origLogPath As String) As _
  Boolean
  On Error GoTo SetOutputPathsError
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
  
  ' delete if it exists already (don't want old test results)
  If strJsonPath <> vbNullString And Dir(strJsonPath) <> vbNullString Then
    Kill strJsonPath
  End If

  ' Also verify log file. Could add more error handling later but for now
  ' just trusting that will be created by calling .ps1 script
  strLogPath = origLogPath
  Exit Function
  
SetOutputPathsError:
  Err.Source = strValidator & "SetOutputPaths"
  Call ValidatorExit(RunCleanup:=False)
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

'  SecondsElapsed = Round(Timer - StartTime, 2)
'  Debug.Print "WriteAlert: " & strAlert & SecondsElapsed
  
  ' Optional: stops ALL code.
  If blnEnd = True Then
    If Not activeDoc Is Nothing Then
      Set activeDoc = Nothing
    End If
    Application.DisplayAlerts = wdAlertsAll
    Application.ScreenUpdating = True
    Application.ScreenRefresh
    On Error GoTo 0
    End
  End If
End Sub



' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
'     PROCEDURES BELOW CAN REFERENCE `genUtils`
' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

' ===== IsbnMain ==============================================================
' Implementation of IsbnCheck that returns a string.

Private Function IsbnMain(FilePath As String) As String
  On Error GoTo IsbnMainError
  
' Make sure relevant file exists, is open
  If genUtils.GeneralHelpers.IsOpen(FilePath) = False Then
    Documents.Open FilePath
  End If

' Set reference to correct document
  Set activeDoc = Documents(FilePath)

' Create dictionary object to receive from IsbnCheck function
  Dim dictIsbn As genUtils.Dictionary
  Set dictIsbn = IsbnCheck(AddFromJson:=False)

  If Not dictIsbn Is Nothing Then
  ' JsonToLog function expects this format
    Dim dictOutput As genUtils.Dictionary
    Set dictOutput = genUtils.ClassHelpers.NewDictionary
    dictOutput.Add "isbn", dictIsbn
    Call genUtils.ClassHelpers.WriteJson(strJsonPath, dictOutput)
  Else
    Err.Raise ValidatorError.err_IsbnMainFail
  End If

' If ISBNs were found, they will be in the "list" element
  If dictIsbn.Exists("list") = True Then
  ' Reduce array elements to a comma-delimited string
    IsbnMain = genUtils.Reduce(dictIsbn.Item("list"), ",")
  Else
    IsbnMain = vbNullString
  End If

  Exit Function
  
IsbnMainError:
  Err.Source = strValidator & "IsbnMain"
  If ErrorChecker(Err, FilePath) = False Then
    Resume
  Else
    Call ValidatorExit
  End If
End Function


' ===== Main ==================================================================
' Once we know we've got the correct references set up, we can build our macro.
' DocPath exists and is a Word file already validated.

Private Function ValidatorMain(DocPath As String) As Boolean
  On Error GoTo ValidatorMainError
  ' Set up variables to store test results
  Dim strKey As String
  Dim blnPass As Boolean
  Dim dictTests As genUtils.Dictionary

' ----- START JSON FILE -------------------------------------------------------
  Call genUtils.ClassHelpers.AddToJson(strJsonPath, "completed", False)
  
' NOTE! Each procedure called returns a dictionary with results of various
' tests. Each will include a "pass" key--a value of "False" means that the
' validator should NOT continue (checked in `ReturnDict` sub).
  
' ----- INITIALIZE ------------------------------------------------------------
  strKey = "initialize"
  Set dictTests = genUtils.Reports.ReportsStartup(DocPath, strAlertPath)
  Call ReturnDict(strKey, dictTests)

' *****************************************************************************
'       ALWAYS CHECK ISBN and STYLES
' *****************************************************************************

' ----- ISBN VALIDATION -------------------------------------------------------
' Check ISBN first, because it can fail to find an ISBN in the body text but
' still run successfully in Bookmaker if ISBN is in file name.

' Actually don't check here, run separate IsbnSearch before calling validator
'  strKey = "isbn"
'  Set dictTests = genUtils.Reports.IsbnCheck
'  Call ReturnDict(strKey, dictTests, QuitIfFailed:=False)

' ----- OVERALL STYLE CHECKS --------------------------------------------------
  strKey = "styled"
  Set dictTests = genUtils.Reports.StyleCheck()
  Call ReturnDict(strKey, dictTests)


' *****************************************************************************
'       CONTINUE IF MS IS STYLED
' *****************************************************************************

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
  strKey = "cleanupMacro"
  Set dictTests = genUtils.CleanupMacro.MacmillanManuscriptCleanup
  Call ReturnDict(strKey, dictTests)
  
' ----- RUN CHAR STYLES MACRO -------------------------------------------------
' To do: convert to function that returns dictionary of test results
  strKey = "characterStyles"
  Set dictTests = genUtils.CharacterStyles.MacmillanCharStyles
  Call ReturnDict(strKey, dictTests)
  
  Set dictTests = Nothing
  
  ValidatorMain = True
  Exit Function
ValidatorMainError:
  Err.Source = strValidator & "ValidatorMain"
  Select Case Err.Number
    Case ValidatorError.err_TestsFailed
      Err.Description = "The test dictionary for `" & strKey & "` returned empty."
      Call ValidatorExit
    Case ValidatorError.err_NoPassKey
      Err.Description = strKey & " dictionary has no `pass` key."
      Call ValidatorExit
    Case Else
      If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
        Resume
      Else
        Call ValidatorExit
      End If
  End Select
  
End Function


' ===== ValidatorCleanup ======================================================
' Cleanup items that we need genUtils ref for. Returns if doc is styled or not.

Private Function ValidatorCleanup(CompleteSuccess As Boolean) As Boolean
  On Error GoTo ValidatorCleanupError

' run before set activeDoc = Nothing
  genUtils.zz_clearFind

' just to keep things tidy
  If Not activeDoc Is Nothing Then
    Set activeDoc = Nothing
  End If
  
  
' Write our final element to `style_check.json` file
  Call genUtils.AddToJson(strJsonPath, "completed", CompleteSuccess)
  
' Read style_check.json into dictionary in order to access styled info
  Dim dictJson As genUtils.Dictionary
  Set dictJson = genUtils.ClassHelpers.ReadJson(strJsonPath)

' Determine if doc is styled or not. If errored before checking styles, item
' won't exist.
  ValidatorCleanup = False
  If Not dictJson Is Nothing Then
    If dictJson.Exists("styled") = True Then
      If dictJson("styled").Exists("pass") = True Then
        ValidatorCleanup = dictJson("styled")("pass")
      End If
    End If
  End If
  Exit Function

ValidatorCleanupError:
  Err.Source = strValidator & "ValidatorCleanup"
' This gets called from ValidatorExit, so skip here and just write alert.
  Call WriteAlert

End Function


' ===== JsonToLog =============================================================
' Converts `style_check.json` to human-readable log entry, and writes to log.

Public Sub JsonToLog()
  On Error GoTo JsonToLogError
' Determine how many seconds code took to run
  SecondsElapsed = Round(Timer - StartTime, 2)
  Call genUtils.AddToJson(strJsonPath, "elaspedTime", SecondsElapsed)

' Write log entry from JSON values
' Should always be there (see previous line)
  If genUtils.IsItThere(strJsonPath) = True Then

  Dim jsonDict As genUtils.Dictionary
    Set jsonDict = genUtils.ReadJson(strJsonPath)
    
    Dim strLog As String  ' string to write to log
  ' Following Matt's formatting for other scripts
    strLog = Format(Now, "yyyy-mm-dd hh:mm:ss AMPM") & "   : " & strProcName _
       & " -- results:" & vbNewLine
    
  ' Loop through `style_check.json` and write to log. Can add more detailed info
  ' in the future.
  
  ' Also don't stress now, but in future could write more generic dict-to-json
  ' function by breaking into multiple functions that call each other:
  ' Value is an array (return all items in comma-delineated string - REDUCE!)
  ' Value is an object (call this function again!)
  ' Value is neither (thus, number, string, boolean) - just write to string.
    Dim strKey1 As Variant
    Dim strKey2 As Variant
    Dim colValues As Collection
    Dim A As Long
    
  ' Anyway, loop through json data and build string to write to log
    With jsonDict
      For Each strKey1 In .Keys
        strLog = strLog & strKey1 & ": "
      ' Value may be another dictionary/object
        If VBA.IsObject(.Item(strKey1)) = True Then
          strLog = strLog & vbNewLine
        ' loop through THIS dictionary
          For Each strKey2 In .Item(strKey1).Keys
            strLog = strLog & vbTab & strKey2 & ": "
          ' Value at this level may be a Collection (how Dictionary class returns
          ' an array from JSON)
            If strKey2 = "list" Then
              If VBA.IsObject(.Item(strKey1).Item(strKey2)) = True Then
                strLog = strLog & vbNewLine & vbTab & vbTab
                Set colValues = .Item(strKey1).Item(strKey2)
              ' Loop through collection, write values
                For A = 1 To colValues.Count
                  If A <> 1 Then
                    ' add comma and space between values
                    strLog = strLog & ", "
                  End If
                  strLog = strLog & colValues(A)
                Next A
              End If
            Else
            ' Pretty sure it's something we can convert to string directly
              strLog = strLog & .Item(strKey1).Item(strKey2)
            End If
            strLog = strLog & vbNewLine
          Next strKey2
        Else
          strLog = strLog & .Item(strKey1) & vbNewLine
        End If
  '      strLog = strLog & vbNewLine
      Next strKey1
    End With
    strLog = strLog & vbNewLine
  '  Debug.Print strLog
    
  ' Write string to log file, which should have been set earlier!
  '  Debug.Print strLogPath
    Call genUtils.AppendTextFile(strLogPath, strLog)
  End If
  
  Exit Sub

JsonToLogError:
' Call WriteAlert not ValidatorCleanup, because called from ValidatorCleanup
  Err.Source = strValidator & "JsonToLog"
  Call WriteAlert(blnEnd:=True)
  
End Sub


' ===== ReturnDict ============================================================
' Process dictionary returned from reports section. If the procedure that made
' the dictionary returns "pass":False then whole macro will quit unless you
' set QuitIfFailed:=False when calling this sub.

Private Sub ReturnDict(SectionKey As String, TestDict As genUtils.Dictionary, _
  Optional QuitIfFailed As Boolean = True)
  On Error GoTo ReturnDictError
  If TestDict Is Nothing Then
    Err.Raise ValidatorError.err_TestsFailed
  Else
    If TestDict.Exists("pass") = True Then
      ' write tests to JSON file
      Call genUtils.AddToJson(strJsonPath, SectionKey, TestDict)
      If TestDict("pass") = False Then
      ' Write our final element to `style_check.json` file
        Call genUtils.AddToJson(strJsonPath, "completed", False)
        If QuitIfFailed = True Then
          SecondsElapsed = Round(Timer - StartTime, 2)
          Debug.Print SectionKey & " complete: " & SecondsElapsed
        ' ValidatorCleanup will end code execution
          Call ValidatorExit
        End If
      End If
    Else
      Err.Raise ValidatorError.err_NoPassKey
    End If
  End If

  SecondsElapsed = Round(Timer - StartTime, 2)
  Debug.Print SectionKey & " complete: " & SecondsElapsed
  
  Exit Sub
  
ReturnDictError:
  Err.Source = strValidator & "ReturnDict"
  Select Case Err.Number
    Case ValidatorError.err_TestsFailed
      Err.Description = "The test dictionary for `" & SectionKey & "` returned empty."
      Call ValidatorExit
    Case ValidatorError.err_NoPassKey
      Err.Description = SectionKey & " dictionary has no `pass` key."
      Call ValidatorExit
    Case Else
      If genUtils.GeneralHelpers.ErrorChecker(Err) = False Then
        Resume
      Else
        Call ValidatorExit
      End If
  End Select

End Sub

' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
'          FOR TESTING
' +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Private Sub ValidatorTest()
'' to simulate being called by ps1
  On Error GoTo TestError
  Dim strFile As String
'  strFile = "01Ayres_STYLED_NotInText_978-1-250-08697-6_2016-May-19"
'  strFile = "02Auster_UNSTYLED_InText_978-1-62779-446-6"
  strFile = "03Leigh_STYLED_InText_978-0-312-38912-3"
'  strFile = "04Brennan_STYLED_InText_2016-May-17"
'  strFile = "05Jahn_STYLED_NotInText_2016-May-04"
'  strFile = "06Black_UNSTYLED_InText_5-25-2016"
'  strFile = "08Newell_UNSTYLED_NotInText_6-29-16"
'  strFile = "09Chaput_UNSTYLED_inText_styles-added"
'  strFile = "10Dietrich_STYLED_InText2_match"
'  strFile = "11Klages_STYLED_InText2_noMatch"
'  strFile = "12Pomfret_UNSTYLED_InText2_match"
'  strFile = "13Segre_UNSTYLED_InText2_noMatch"
'  strFile = "14Meadows_less-than-half"

  Call Validator.Launch("C:\Users\erica.warren\Desktop\validator_test\" & strFile & ".docx", _
  "C:\Users\erica.warren\Desktop\validator_test\LOG_" & strFile & ".txt")
  Exit Sub

TestError:
  Debug.Print Err.Number & ": " & Err.Description
End Sub


Private Sub IsbnTest()
'' to simulate being called by ps1
  On Error GoTo TestError
  Dim strDir As String: strDir = "C:\Users\erica.warren\Desktop\validator_test\"
  Dim strLog As String
  Dim strThisFile As String
  Dim strReturnedIsbn As String
  Dim A As Long
  
  Dim strFile(1 To 13) As String
  strFile(1) = "01Ayres_STYLED_NotInText_978-1-250-08697-6_2016-May-19"
  strFile(2) = "02Auster_UNSTYLED_InText_978-1-62779-446-6"
  strFile(3) = "03Leigh_STYLED_InText_978-0-312-38912-3"
  strFile(4) = "04Brennan_STYLED_InText_2016-May-17"
  strFile(5) = "05Jahn_STYLED_NotInText_2016-May-04"
  strFile(6) = "06Black_UNSTYLED_InText_5-25-2016"
  strFile(7) = "08Newell_UNSTYLED_NotInText_6-29-16"
  strFile(8) = "09Chaput_UNSTYLED_inText_styles-added"
  strFile(9) = "10Dietrich_STYLED_InText2_match"
  strFile(10) = "11Klages_STYLED_InText2_noMatch"
  strFile(11) = "12Pomfret_UNSTYLED_InText2_match"
  strFile(12) = "13Segre_UNSTYLED_InText2_noMatch"
  strFile(13) = "14Meadows_less-than-half"

  For A = 1 To UBound(strFile)
    Debug.Print A & ": " & strFile(A)
    strLog = strDir & strFile(A) & ".txt"
    strThisFile = strDir & strFile(A) & ".docx"
    strReturnedIsbn = Validator.IsbnSearch(strThisFile, strLog)
    lngCleanupCount = 0
    If strReturnedIsbn = vbNullString Then
      Debug.Print "No Isbn found"
    Else
      Debug.Print "Found Isbns: " & strReturnedIsbn
    End If
    Debug.Print "COMPLETED!" & vbNewLine
  Next A
  
  
'  Dim strFile As String
'  strFile = "07Tomasky_UNSTYLED_NotInText_9781627796767_2016-5-19"
'  strLog = strDir & strFile & ".txt"
'  strThisFile = strDir & strFile & ".docx"
'  strReturnedIsbn = Validator.IsbnSearch(strThisFile, strLog)
'
'  If strReturnedIsbn = vbNullString Then
'    Debug.Print "No Isbn found"
'  Else
'    Debug.Print "Found Isbns: " & strReturnedIsbn
'  End If

  Exit Sub

TestError:
  Debug.Print Err.Number & ": " & Err.Description
End Sub
