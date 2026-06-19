// Test OCR approach: pdftoppm (render to image) → Tesseract.js (OCR to text)
const { execSync } = require('child_process');
const { createWorker } = require('tesseract.js');
const fs = require('fs');
const path = require('path');

const PDFTOPPM = path.join(__dirname, 'poppler', 'poppler-24.08.0', 'Library', 'bin', 'pdftoppm.exe');
const BOOKS_DIR = path.join(__dirname, '..', 'books');
const TEMP_DIR = path.join(__dirname, 'temp_ocr');

async function testOCR(pdfFileName, startPage, endPage) {
  if (!fs.existsSync(TEMP_DIR)) fs.mkdirSync(TEMP_DIR, { recursive: true });
  
  const pdfPath = path.join(BOOKS_DIR, pdfFileName);
  console.log(`\nTesting OCR on: ${pdfFileName}`);
  console.log(`Pages ${startPage}-${endPage}`);
  
  // Step 1: Render PDF pages to PNG images using pdftoppm
  console.log('\n1. Rendering PDF pages to images...');
  const prefix = path.join(TEMP_DIR, 'page');
  try {
    execSync(`"${PDFTOPPM}" -f ${startPage} -l ${endPage} -r 200 -png "${pdfPath}" "${prefix}"`, {
      timeout: 60000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (e) {
    console.error('pdftoppm error:', e.stderr?.toString()?.substring(0, 200));
    return;
  }
  
  // Find generated images
  const images = fs.readdirSync(TEMP_DIR)
    .filter(f => f.startsWith('page') && f.endsWith('.png'))
    .sort();
  console.log(`   Generated ${images.length} page images`);
  
  // Step 2: OCR each image
  console.log('\n2. Running OCR...');
  const worker = await createWorker('eng');
  
  let fullText = '';
  for (const img of images) {
    const imgPath = path.join(TEMP_DIR, img);
    console.log(`   OCR: ${img} (${(fs.statSync(imgPath).size / 1024).toFixed(0)} KB)`);
    
    const { data } = await worker.recognize(imgPath);
    fullText += data.text + '\n\n--- PAGE BREAK ---\n\n';
    
    // Clean up image
    fs.unlinkSync(imgPath);
  }
  
  await worker.terminate();
  
  // Step 3: Show results
  console.log('\n3. Results:');
  console.log('─'.repeat(60));
  console.log(fullText.substring(0, 3000));
  console.log('─'.repeat(60));
  console.log(`\nTotal chars: ${fullText.length}`);
  
  const alphaRatio = (fullText.match(/[a-zA-Z]/g) || []).length / Math.max(fullText.length, 1);
  console.log(`Alpha ratio: ${(alphaRatio * 100).toFixed(1)}%`);
  console.log(alphaRatio > 0.3 ? '✓ READABLE - OCR works!' : '✗ Still issues');
  
  return fullText;
}

const pdfFile = process.argv[2] || 'NCERT-Class-10-Science.pdf';
const startPage = parseInt(process.argv[3] || '3');
const endPage = parseInt(process.argv[4] || '5');

testOCR(pdfFile, startPage, endPage)
  .then(() => {
    // Cleanup
    try { fs.rmSync(TEMP_DIR, { recursive: true }); } catch {}
    console.log('\nDone!');
  })
  .catch(e => console.error('Error:', e));
