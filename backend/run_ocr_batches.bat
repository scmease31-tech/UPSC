@echo off
echo ============================================
echo   Auto OCR Batch Runner - UPSC Books
echo   Processing 3 books per batch
echo ============================================

:loop
echo.
echo --- Starting next OCR batch (3 books) ---
"C:\Program Files\nodejs\node.exe" --max-old-space-size=2048 --expose-gc fix_books.js --batch 3 --ocr-only
echo.
echo --- Batch complete. Checking remaining... ---

REM Check if all done by looking for "Done=0" in output
"C:\Program Files\nodejs\node.exe" -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('fix_progress.json','utf8'));const total=40;const done=p.ocr_extracted.length;console.log('OCR Progress: '+done+'/'+total);if(done>=total){console.log('ALL OCR COMPLETE');process.exit(1);}else{console.log('Continuing...');process.exit(0);}"
if %errorlevel% NEQ 0 goto done

echo Pausing 5 seconds before next batch...
timeout /t 5 /nobreak >nul
goto loop

:done
echo.
echo ============================================
echo   ALL OCR EXTRACTION COMPLETE!
echo   Run: node fix_books.js --upload
echo ============================================
pause
