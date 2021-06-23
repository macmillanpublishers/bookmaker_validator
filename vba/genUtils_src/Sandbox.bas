Attribute VB_Name = "Sandbox"
Option Explicit

Private Sub newline()
  Dim pgh As Paragraph
  Dim strPrint(1 To 16) As Boolean
  
  With ActiveDocument.Range
    .InsertAfter "CR" & vbCr
    .InsertAfter "LF" & vbLf
    .InsertAfter "CRLF" & vbCrLf
    .InsertAfter "NEWLINE" & vbNewLine
    .InsertAfter "10" & Chr(10)
    .InsertAfter "13" & Chr(13)
    .InsertAfter "13 and 10" & Chr(13) & Chr(10)
    .InsertAfter "10 and 13" & Chr(10) & Chr(13)
  End With
  
  For Each pgh In ActiveDocument.Paragraphs
    If Right(pgh.Range.FormattedText, 1) = vbCr Then
      strPrint(1) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = vbLf Then
      strPrint(2) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = vbCrLf Then
      strPrint(3) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = vbNewLine Then
      strPrint(4) = True
    End If
    
    
    If Right(pgh.Range.FormattedText, 2) = vbCr Then
      strPrint(5) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = vbLf Then
      strPrint(6) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = vbCrLf Then
      strPrint(7) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = vbNewLine Then
      strPrint(8) = True
    End If
    
    
    If Right(pgh.Range.FormattedText, 1) = Chr(10) Then
      strPrint(9) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = Chr(13) Then
      strPrint(10) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = Chr(10) & Chr(13) Then
      strPrint(11) = True
    End If
    If Right(pgh.Range.FormattedText, 1) = Chr(13) & Chr(10) Then
      strPrint(12) = True
    End If

    If Right(pgh.Range.FormattedText, 2) = Chr(10) Then
      strPrint(13) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = Chr(13) Then
      strPrint(14) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = Chr(10) & Chr(13) Then
      strPrint(15) = True
    End If
    If Right(pgh.Range.FormattedText, 2) = Chr(13) & Chr(10) Then
      strPrint(16) = True
    End If
    
    DebugPrint pgh.Range.Text & vbNewLine & _
      "1 chr CR:         " & strPrint(1) & vbNewLine & _
      "1 chr LF:         " & strPrint(2) & vbNewLine & _
      "1 chr CRLF:       " & strPrint(3) & vbNewLine & _
      "1 chr NEWLINE:    " & strPrint(4) & vbNewLine & vbNewLine & _
      "2 chr CR:         " & strPrint(5) & vbNewLine & _
      "2 chr LF:         " & strPrint(6) & vbNewLine & _
      "2 chr CRLF:       " & strPrint(7) & vbNewLine & _
      "2 chr NEWLINE:    " & strPrint(8) & vbNewLine & vbNewLine & _
      "1 chr 10:         " & strPrint(9) & vbNewLine & _
      "1 chr 13:         " & strPrint(10) & vbNewLine & _
      "1 chr 10 & 13:    " & strPrint(11) & vbNewLine & _
      "1 chr 13 & 10:    " & strPrint(12) & vbNewLine & vbNewLine & _
      "2 chr 10:         " & strPrint(13) & vbNewLine & _
      "2 chr 13:         " & strPrint(14) & vbNewLine & _
      "2 chr 10 & 13:    " & strPrint(15) & vbNewLine & _
      "2 chr 13 & 10:    " & strPrint(16) & vbNewLine & vbNewLine
  Next
End Sub

Private Sub BreakTest()
  Dim ParaIndexArray(1 To 3) As Long
  ParaIndexArray(1) = 1
  ParaIndexArray(2) = 4
  ParaIndexArray(3) = 8
  
  Dim rangeArray() As Variant
  Dim rngSection As Range
  Dim lngParaCount As Long: lngParaCount = ActiveDocument.Paragraphs.Count
  
  Dim lngLBound As Long
  Dim lngUBound As Long
  lngLBound = LBound(ParaIndexArray)
  lngUBound = UBound(ParaIndexArray)
  ReDim Preserve rangeArray(lngLBound To lngUBound)
  
' G is array index number
  Dim G As Long
  Dim lngStart As Long
  Dim lngEnd As Long

' Loop through passed array
  For G = lngLBound To lngUBound
  ' Determine start and end section index numbers
    lngStart = ParaIndexArray(G)
'    DebugPrint lngStart
    If G < lngUBound Then
      lngEnd = ParaIndexArray(G + 1) - 1
    Else
      lngEnd = lngParaCount
    End If
'    DebugPrint lngEnd
    Dim lngColor As Long
  ' Set range based on those start/end points
    With ActiveDocument
      Set rngSection = .Range(Start:=.Paragraphs(lngStart).Range.Start, _
        End:=.Paragraphs(lngEnd).Range.End)
      
      ' DEBUGGING
      If G Mod 2 = 0 Then
        lngColor = wdColorAqua
      Else
        lngColor = wdColorPink
      End If
      rngSection.Shading.BackgroundPatternColor = lngColor
    ' DEBUGGING
    
    
    End With
  ' Add range to array
    Set rangeArray(G) = rngSection
  Next G
  
  Dim rngPara1 As Range
  Dim rngParaLast As Range
  Dim rngSect As Range
  Dim A As Long

' Now loop through ranges and figure out this nonsense.



  For A = UBound(rangeArray) To LBound(rangeArray) Step -1
    Set rngPara1 = rangeArray(A).Paragraphs.First.Range
    Set rngParaLast = rangeArray(A).Paragraphs.Last.Range
    ' don't add section break to 1st para
    If A > LBound(rangeArray) Then
      rngPara1.Collapse Direction:=wdCollapseStart
      rngPara1.InsertBreak Type:=wdSectionBreakNextPage
    End If
    
    If A < UBound(rangeArray) Then
       rngParaLast.Collapse Direction:=wdCollapseEnd
       rngParaLast.InsertAfter vbNewLine
       rngParaLast.Style = "Heading 1"
    End If
  
  Next A

  Dim objSection As Section
  For Each objSection In ActiveDocument.Sections
    Debug.Print objSection.Range.Paragraphs.First.Range.Text
  Next objSection
  
  
'  For Each objSection In ActiveDocument.Sections
'
'    Debug.Print "Grab Paragraph " & A
'    Set rngPara2 = ActiveDocument.Paragraphs(A).Range
'    Debug.Print "Paragraph text: " & rngPara2.Characters(1)
'    rngPara2.InsertBreak Type:=wdSectionBreakNextPage
'
'  Next objSection

End Sub

Private Sub Test()
  Application.DisplayAlerts = wdAlertsNone
  Dim strFile As String
  Dim strDir As String
  Dim dictTests As genUtils.Dictionary
  strDir = "C:\Users\erica.warren\Desktop\validator\"
  strFile = "validator-test"
    
  Set activeDoc = Documents.Open(strDir & strFile & ".docx")
  Set dictTests = CleanupMacro.MacmillanManuscriptCleanup()

  Exit Sub
  
End Sub




