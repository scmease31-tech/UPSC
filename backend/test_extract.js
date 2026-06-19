// Quick test: extract text from a corrupted PDF using pdfjs-dist
const path = require('path');
const fs = require('fs');

async function testExtract(pdfFile) {
  const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs');
  
  const pdfPath = path.join(__dirname, '..', 'books', pdfFile);
  console.log(`Testing: ${pdfFile}`);
  console.log(`Size: ${(fs.statSync(pdfPath).size / 1024 / 1024).toFixed(1)} MB`);
  
  const data = new Uint8Array(fs.readFileSync(pdfPath));
  const doc = await pdfjsLib.getDocument({ data, useSystemFonts: true }).promise;
  
  console.log(`Pages: ${doc.numPages}`);
  
  // Extract first 3 pages as test
  let text = '';
  const pagesToTest = Math.min(5, doc.numPages);
  for (let i = 1; i <= pagesToTest; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    const pageText = content.items.map(item => item.str).join(' ');
    text += pageText + '\n\n';
    page.cleanup();
  }
  
  doc.cleanup();
  doc.destroy();
  
  console.log(`\n--- First ${pagesToTest} pages sample ---`);
  console.log(text.substring(0, 2000));
  console.log(`\n--- Total chars: ${text.length} ---`);
  
  // Check if content is readable
  const alphaRatio = (text.match(/[a-zA-Z]/g) || []).length / Math.max(text.length, 1);
  console.log(`Alpha ratio: ${(alphaRatio * 100).toFixed(1)}%`);
  console.log(alphaRatio > 0.3 ? '✓ READABLE' : '✗ STILL CORRUPTED');
}

const testFile = process.argv[2] || 'NCERT-Class-10-Science.pdf';
testExtract(testFile).catch(e => console.error('Error:', e.message));
