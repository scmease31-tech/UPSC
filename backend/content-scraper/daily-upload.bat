@echo off
REM ============================================================================
REM  UPSC Daily Upload - double-click this file
REM
REM  Put the day's PDFs in your Downloads folder (named as usual, e.g.
REM  "Daily Vocabulary 13-07-2026.pdf", "IE Delhi 13-07-2026.pdf",
REM  "TH Delhi 13-07-2026.pdf", "All English Editorials 13-7.pdf"),
REM  then double-click this file. It finds them, uploads the content, and
REM  shows a summary.
REM
REM  To scan a different folder, run from a terminal:
REM     daily-upload.bat --dir "D:\path\to\pdfs"
REM  To preview without uploading:
REM     daily-upload.bat --dry-run
REM ============================================================================

setlocal

REM Auto-detect the newest Firebase Admin key in Downloads if not already set.
if not defined GOOGLE_APPLICATION_CREDENTIALS (
  for /f "delims=" %%F in ('dir /b /a-d /o-d "%USERPROFILE%\Downloads\*firebase-adminsdk*.json" 2^>nul') do (
    if not defined GOOGLE_APPLICATION_CREDENTIALS set "GOOGLE_APPLICATION_CREDENTIALS=%USERPROFILE%\Downloads\%%F"
  )
)

if not defined GOOGLE_APPLICATION_CREDENTIALS (
  echo [ERROR] No Firebase Admin service-account JSON found in %USERPROFILE%\Downloads.
  echo Download one from Firebase Console ^> Project Settings ^> Service accounts,
  echo or set GOOGLE_APPLICATION_CREDENTIALS to its path, then retry.
  echo.
  pause
  exit /b 1
)

echo Using credentials: %GOOGLE_APPLICATION_CREDENTIALS%
echo.

node "%~dp0daily-ingest.js" %*

echo.
echo ----------------------------------------------------------------
echo Finished. You can close this window.
pause
endlocal
