// Test pdf2json extraction on corrupted NCERT PDFs
const PDFParser = require('pdf2json');
const path = require('path');

const pdfFile = process.argv[2] || 'NCERT-Class-10-Science.pdf';
const pdfPath = path.join(__dirname, '..', 'books', pdfFile);

console.log(`Testing pdf2json on: ${pdfFile}`);

const pdfParser = new PDFParser();

pdfParser.on('pdfParser_dataReady', (pdfData) => {
  let text = '';
  // Get first 3 pages
  const pages = pdfData.Pages.slice(0, 5);
  for (const page of pages) {
    for (const textItem of page.Texts) {
      const str = decodeURIComponent(textItem.R.map(r => r.T).join(''));
      text += str + ' ';
    }
    text += '\n\n--- PAGE BREAK ---\n\n';
  }
  
  console.log(`Total pages: ${pdfData.Pages.length}`);
  console.log(`\n--- Sample (first 5 pages) ---`);
  console.log(text.substring(0, 2000));
  
  const alphaRatio = (text.match(/[a-zA-Z]/g) || []).length / Math.max(text.length, 1);
  console.log(`\nAlpha ratio: ${(alphaRatio * 100).toFixed(1)}%`);
  console.log(alphaRatio > 0.3 ? '✓ READABLE' : '✗ STILL CORRUPTED');
});

pdfParser.on('pdfParser_dataError', (err) => {
  console.error('Error:', err.parserError);
});

pdfParser.loadPDF(pdfPath);
