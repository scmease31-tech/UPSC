// ==========================================
// UPSC Daily Edge — Automated Content Pipeline
// Google Apps Script Backend (v2 — Rewritten)
// ==========================================
//
// SETUP INSTRUCTIONS:
// 1. Go to https://script.google.com → New Project
// 2. Delete default Code.gs content, paste this ENTIRE file
// 3. Go to Project Settings (gear icon) → Script Properties → Add these:
//    ┌──────────────────────┬───────────────────────────────────────────────┐
//    │ Property Name        │ Value                                        │
//    ├──────────────────────┼───────────────────────────────────────────────┤
//    │ TELEGRAM_BOT_TOKEN   │ Your Telegram bot token                      │
//    │ GEMINI_API_KEY       │ Your Gemini API key (primary)                │
//    │ GEMINI_API_KEYS      │ Comma-separated keys for rotation (optional) │
//    │ DRIVE_FOLDER_ID      │ Your Google Drive folder ID                  │
//    │ FIREBASE_PROJECT_ID  │ e.g. upsc-app-e2475                          │
//    │ SERVICE_ACCOUNT_JSON │ Paste ENTIRE content of service account JSON  │
//    │ WEBAPP_URL           │ Your deployed web app URL (the /exec URL)     │
//    └──────────────────────┴───────────────────────────────────────────────┘
// 4. Deploy → New deployment → Type: Web app
//      Execute as: Me | Who has access: Anyone
// 5. Copy the web app URL → Save it as WEBAPP_URL in Script Properties
// 6. Select function "setupAll" in the editor and click ▶ Run
//    (This sets webhook + creates the 1-minute queue trigger + daily summary)
// 7. Done! Send PDFs to your bot.
// ==========================================

// --- Configuration ---
function getConfig() {
    var props = PropertiesService.getScriptProperties();
    return {
        TELEGRAM_TOKEN: props.getProperty('TELEGRAM_BOT_TOKEN'),
        GEMINI_KEY: props.getProperty('GEMINI_API_KEY'),
        DRIVE_FOLDER_ID: props.getProperty('DRIVE_FOLDER_ID'),
        ADMIN_CHAT_ID: props.getProperty('ADMIN_CHAT_ID') || '',
        PROJECT_ID: props.getProperty('FIREBASE_PROJECT_ID'),
        SERVICE_ACCOUNT: JSON.parse(props.getProperty('SERVICE_ACCOUNT_JSON') || '{}')
    };
}

// Returns all available Gemini API keys from Script Properties
function getGeminiKeys() {
    var props = PropertiesService.getScriptProperties();
    var multiKeys = props.getProperty('GEMINI_API_KEYS') || '';
    var singleKey = props.getProperty('GEMINI_API_KEY') || '';

    var keys = [];
    if (multiKeys) {
        keys = multiKeys.split(',').map(function(k) { return k.trim(); }).filter(function(k) { return k.length > 0; });
    }
    if (singleKey && keys.indexOf(singleKey) === -1) {
        keys.unshift(singleKey);
    }
    if (keys.length === 0) {
        Logger.log('WARNING: No Gemini API keys configured in Script Properties');
    }
    return keys;
}

var IST_TIMEZONE = 'Asia/Kolkata';

function getTodayIST() {
    return Utilities.formatDate(new Date(), IST_TIMEZONE, 'yyyy-MM-dd');
}

function getYesterdayIST() {
    var d = new Date();
    d.setDate(d.getDate() - 1);
    return Utilities.formatDate(d, IST_TIMEZONE, 'yyyy-MM-dd');
}

function shortHash(str) {
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
        hash = ((hash << 5) - hash) + str.charCodeAt(i);
        hash |= 0;
    }
    return Math.abs(hash).toString(36).substring(0, 6);
}

// Extract date from filename (e.g. "TH Delhi 12-03-2026.pdf" → "2026-03-12")
function extractDateFromFilename(fileName) {
    var match = fileName.match(/(\d{1,2})[\-~_\.](\d{1,2})[\-~_\.](\d{4})/);
    if (match) {
        var day = ('0' + match[1]).slice(-2);
        var month = ('0' + match[2]).slice(-2);
        var year = match[3];
        return year + '-' + month + '-' + day;
    }
    return null;
}

// ==========================================
//  TELEGRAM MESSAGE DEDUPLICATION
//  Every message type per file is sent EXACTLY ONCE
// ==========================================

// Send a Telegram message only if this exact messageKey hasn't been sent before (within 24h)
// messageKey format: "<chatId>_<fileEditionKey>_<stage>" e.g. "123_th_delhi_20-3_received"
function sendTelegramMessageOnce(chatId, messageKey, text) {
    var cache = CacheService.getScriptCache();
    var cacheKey = 'msg_sent_' + messageKey;
    if (cache.get(cacheKey)) {
        Logger.log('Message already sent, skipping: ' + messageKey);
        return false;
    }
    cache.put(cacheKey, '1', 86400); // 24h TTL
    sendTelegramMessage(chatId, text);
    return true;
}

// Build a stable edition key from a filename (for deduplication)
function buildEditionKey(fileName) {
    return fileName.replace(/\.pdf$/i, '').replace(/\s+/g, '_').toLowerCase();
}

// Rotate through all available keys, trying each until one succeeds
function processWithGeminiRotation(pdfBlob, newspaper, chatId) {
    var keys = getGeminiKeys();
    if (keys.length === 0) {
        Logger.log('ERROR: No Gemini API keys configured');
        return { articles: null, error: 'No Gemini API keys configured' };
    }

    Logger.log('Gemini key rotation: ' + keys.length + ' key(s) available');
    var lastError = '';
    var anyQuotaHit = false;

    for (var k = 0; k < keys.length; k++) {
        var keyLabel = 'Key-' + (k + 1) + '/' + keys.length;
        Logger.log('Trying ' + keyLabel + '...');

        var result = processWithGemini(pdfBlob, newspaper, keys[k], chatId);

        if (result.articles && result.articles.length > 0) {
            Logger.log(keyLabel + ' succeeded: ' + result.articles.length + ' articles');
            return result;
        }

        lastError = result.error || 'unknown';
        var err = lastError.toLowerCase();
        var isRateLimit = err.indexOf('429') !== -1 || err.indexOf('quota') !== -1 ||
            err.indexOf('rate') !== -1 || err.indexOf('resource_exhausted') !== -1 ||
            (err.indexOf('403') !== -1 && err.indexOf('permission') === -1);

        if (isRateLimit) anyQuotaHit = true;

        if (isRateLimit && k < keys.length - 1) {
            Logger.log(keyLabel + ' hit rate limit, waiting 10s before next key...');
            Utilities.sleep(10000);
            continue;
        }

        if (k < keys.length - 1) {
            Logger.log(keyLabel + ' failed (' + lastError + '), waiting 5s before next key...');
            Utilities.sleep(5000);
            continue;
        }
    }

    // Determine if ALL keys failed specifically due to rate limits / quota
    // anyQuotaHit tracks if ANY key hit rate limit (not just the last one)
    Logger.log('ALL ' + keys.length + ' Gemini keys exhausted. Last: ' + lastError + ' (quota issue: ' + anyQuotaHit + ')');
    return { articles: null, error: 'All ' + keys.length + ' API keys exhausted. Last error: ' + lastError, isQuotaExhausted: anyQuotaHit };
}

// ==========================================
//  TELEGRAM WEBHOOK HANDLERS
// ==========================================

function doPost(e) {
    var chatId = null;
    try {
        var update = JSON.parse(e.postData.contents);

        // Deduplicate Telegram updates by update_id
        if (update.update_id) {
            var cache = CacheService.getScriptCache();
            var cacheKey = 'tg_upd_' + update.update_id;
            if (cache.get(cacheKey)) {
                return ContentService.createTextOutput('OK');
            }
            cache.put(cacheKey, '1', 600); // 10 min TTL
        }

        // Handle all Telegram update types
        var messages = [];
        if (update.message) messages.push(update.message);
        if (update.channel_post) messages.push(update.channel_post);
        // Ignore edited messages — only process new sends
        // This prevents re-processing when someone edits a caption

        for (var i = 0; i < messages.length; i++) {
            chatId = messages[i].chat && messages[i].chat.id;
            handleMessage(messages[i]);
        }
        return ContentService.createTextOutput('OK');
    } catch (err) {
        Logger.log('doPost error: ' + err.message + '\n' + err.stack);
        if (chatId) {
            try {
                sendTelegramMessage(chatId, '❌ <b>Error:</b> ' + err.message);
            } catch (e2) { /* ignore */ }
        }
        return ContentService.createTextOutput('ERROR');
    }
}

function doGet(e) {
    return HtmlService.createHtmlOutput(getUploadPageHtml())
        .setTitle('UPSC Daily Edge — Upload PDF')
        .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function getWebAppUrl() {
    var props = PropertiesService.getScriptProperties();
    var savedUrl = props.getProperty('WEBAPP_URL');
    if (savedUrl) return savedUrl;
    var url = ScriptApp.getService().getUrl();
    if (url.endsWith('/dev')) {
        url = url.replace(/\/dev$/, '/exec');
    }
    return url;
}

// Server-side handler for web upload form
function uploadFile(formData) {
    var blob = formData.file;
    if (!blob) throw new Error('No file selected.');
    var fileName = blob.getName();
    if (!fileName.toLowerCase().endsWith('.pdf')) {
        throw new Error('Only PDF files are accepted. Got: ' + fileName);
    }
    var config = getConfig();
    var driveFile = saveToDrive(blob, fileName, config.DRIVE_FOLDER_ID);
    driveFile.setDescription('queued:web');
    Logger.log('Web upload saved: ' + fileName);
    return '✅ Saved to Drive: ' + fileName + '\n⏰ It will be auto-processed within 1 minute.';
}

// HTML for the web upload page (handles >20MB files that Telegram can't download)
function getUploadPageHtml() {
    var lines = [
        '<!DOCTYPE html>',
        '<html><head>',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
        '<style>',
        '* { box-sizing: border-box; margin: 0; padding: 0; }',
        'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;',
        '  background: linear-gradient(135deg, #0a1628 0%, #0d2137 50%, #0a1628 100%);',
        '  color: #e0e0e0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }',
        '.container { max-width: 480px; width: 100%; }',
        '.card { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1);',
        '  border-radius: 20px; padding: 32px 24px; backdrop-filter: blur(10px); }',
        'h1 { color: #26a69a; font-size: 22px; margin-bottom: 4px; }',
        '.subtitle { color: #888; font-size: 14px; margin-bottom: 24px; }',
        '.upload-area { border: 2px dashed rgba(38,166,154,0.3); border-radius: 16px;',
        '  padding: 36px 20px; text-align: center; cursor: pointer; transition: all 0.3s;',
        '  background: rgba(255,255,255,0.02); }',
        '.upload-area:hover, .upload-area.dragover { border-color: #26a69a; background: rgba(38,166,154,0.08); }',
        '.upload-icon { font-size: 44px; margin-bottom: 10px; }',
        '.upload-text { color: #999; font-size: 14px; }',
        '.file-info { color: #26a69a; font-weight: 600; margin-top: 10px; word-break: break-all; font-size: 14px; }',
        '.btn { display: block; width: 100%; padding: 14px; border: none; border-radius: 12px;',
        '  background: linear-gradient(135deg, #26a69a, #2bbbad); color: white; font-size: 16px;',
        '  font-weight: 700; cursor: pointer; margin-top: 20px; transition: opacity 0.3s; letter-spacing: 0.5px; }',
        '.btn:disabled { opacity: 0.4; cursor: not-allowed; }',
        '.btn:hover:not(:disabled) { opacity: 0.9; }',
        '.status { text-align: center; margin-top: 14px; padding: 12px 16px; border-radius: 10px;',
        '  font-size: 14px; display: none; line-height: 1.5; }',
        '.status.show { display: block; }',
        '.status.success { background: rgba(38,166,154,0.15); color: #26a69a; }',
        '.status.error { background: rgba(255,82,82,0.15); color: #ff5252; }',
        '.status.loading { background: rgba(255,255,255,0.06); color: #aaa; }',
        '.note { text-align: center; color: #666; font-size: 12px; margin-top: 16px; }',
        'input[type=file] { display: none; }',
        '</style>',
        '</head><body>',
        '<div class="container"><div class="card">',
        '  <h1>\ud83d\udcf0 UPSC Daily Edge</h1>',
        '  <p class="subtitle">Upload newspaper PDF for AI processing</p>',
        '  <form id="uploadForm">',
        '    <div class="upload-area" id="dropZone">',
        '      <div class="upload-icon">\ud83d\udcc4</div>',
        '      <div class="upload-text">Tap to select PDF or drag & drop</div>',
        '      <div class="file-info" id="fileInfo"></div>',
        '    </div>',
        '    <input type="file" id="fileInput" name="file" accept=".pdf,application/pdf">',
        '    <button type="submit" class="btn" id="submitBtn" disabled>\u2b06\ufe0f Upload & Process</button>',
        '  </form>',
        '  <div class="status" id="status"></div>',
        '  <p class="note">No size limit \u2022 Auto-processed within 15 min \u2022 Use /today in bot to check</p>',
        '</div></div>',
        '<script>',
        'var fileInput = document.getElementById("fileInput");',
        'var fileInfo = document.getElementById("fileInfo");',
        'var submitBtn = document.getElementById("submitBtn");',
        'var status = document.getElementById("status");',
        'var dropZone = document.getElementById("dropZone");',
        'var form = document.getElementById("uploadForm");',
        '',
        'dropZone.addEventListener("click", function() { fileInput.click(); });',
        '',
        'fileInput.addEventListener("change", function() {',
        '  if (this.files.length > 0) {',
        '    var f = this.files[0];',
        '    fileInfo.textContent = f.name + " (" + (f.size / 1024 / 1024).toFixed(1) + " MB)";',
        '    submitBtn.disabled = false;',
        '    status.className = "status"; }',
        '});',
        '',
        'dropZone.addEventListener("dragover", function(e) { e.preventDefault(); this.classList.add("dragover"); });',
        'dropZone.addEventListener("dragleave", function() { this.classList.remove("dragover"); });',
        'dropZone.addEventListener("drop", function(e) {',
        '  e.preventDefault(); this.classList.remove("dragover");',
        '  var files = e.dataTransfer.files;',
        '  if (files.length > 0) {',
        '    fileInput.files = files;',
        '    var f = files[0];',
        '    fileInfo.textContent = f.name + " (" + (f.size / 1024 / 1024).toFixed(1) + " MB)";',
        '    submitBtn.disabled = false;',
        '    status.className = "status"; }',
        '});',
        '',
        'form.addEventListener("submit", function(e) {',
        '  e.preventDefault();',
        '  submitBtn.disabled = true;',
        '  submitBtn.textContent = "\u23f3 Uploading...";',
        '  status.className = "status show loading";',
        '  status.textContent = "Uploading PDF to Google Drive...";',
        '  google.script.run',
        '    .withSuccessHandler(function(msg) {',
        '      status.className = "status show success";',
        '      status.textContent = msg;',
        '      submitBtn.textContent = "\u2705 Upload Complete!";',
        '      setTimeout(function() {',
        '        submitBtn.textContent = "\u2b06\ufe0f Upload & Process";',
        '        submitBtn.disabled = true;',
        '        fileInfo.textContent = "";',
        '        fileInput.value = "";',
        '      }, 4000);',
        '    })',
        '    .withFailureHandler(function(err) {',
        '      status.className = "status show error";',
        '      status.textContent = "\u274c " + err.message;',
        '      submitBtn.textContent = "\u2b06\ufe0f Upload & Process";',
        '      submitBtn.disabled = false;',
        '    })',
        '    .uploadFile(this);',
        '});',
        '</script>',
        '</body></html>'
    ];
    return lines.join('\n');
}

function handleMessage(message) {
    var chatId = message.chat.id;

    // Remember admin chat ID for notifications (first user to interact)
    var props = PropertiesService.getScriptProperties();
    if (!props.getProperty('ADMIN_CHAT_ID')) {
        props.setProperty('ADMIN_CHAT_ID', String(chatId));
    }

    // ── MESSAGE TIMESTAMP CHECK ──
    // Accept messages sent today or yesterday (forwarded messages from channels may have yesterday's timestamp)
    var today = getTodayIST();
    var yesterday = getYesterdayIST();
    var msgDate = message.date ? new Date(message.date * 1000) : new Date();
    var msgDateStr = Utilities.formatDate(msgDate, IST_TIMEZONE, 'yyyy-MM-dd');

    if (msgDateStr !== today && msgDateStr !== yesterday) {
        Logger.log('Skipping old message from ' + msgDateStr + ' (today is ' + today + ')');
        return;
    }

    // PDF document received
    if (message.document) {
        handleDocumentMessage(chatId, message.document, today, yesterday);
    } else if (message.text) {
        handleTextCommand(chatId, message.text);
    }
}

// ── DOCUMENT HANDLER ──
// Processes a single PDF document with full deduplication.
// Every message type per file is sent EXACTLY ONCE per day (no repeat spam).
// Accepts newspapers from today OR yesterday.
// Files are queued for AI processing and picked up by the 1-minute trigger.
function handleDocumentMessage(chatId, doc, today, yesterday) {
    var fileName = doc.file_name || 'newspaper.pdf';
    var mimeType = doc.mime_type || '';
    var fileSizeBytes = doc.file_size || 0;
    var fileSizeMB = (fileSizeBytes / (1024 * 1024)).toFixed(1);
    var editionKey = buildEditionKey(fileName);
    var telegramFileId = doc.file_id;
    var cache = CacheService.getScriptCache();

    // ── Gate 1: PDF check ──
    if (mimeType !== 'application/pdf' && !fileName.toLowerCase().endsWith('.pdf')) {
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_notpdf',
            '⚠️ Please send a PDF file. Received: ' + mimeType);
        return;
    }

    // ── Gate 2: Already handled today? (processed / rejected / queued) ──
    // Check these FIRST — if we already handled this file today, stay silent or send one-time notice
    var processedKey = 'processed_ok_' + today + '_' + editionKey;
    if (cache.get(processedKey)) {
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_already',
            '✅ <b>Already processed:</b> ' + fileName + '\n📊 Use /today to see article count.');
        return;
    }

    var rejectedKey = 'rejected_' + today + '_' + editionKey;
    if (cache.get(rejectedKey)) {
        // Already told the user this file was rejected — stay completely silent
        Logger.log('Already rejected today, silent skip: ' + fileName);
        return;
    }

    var queuedCacheKey = 'queued_' + today + '_' + editionKey;
    if (cache.get(queuedCacheKey)) {
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_alreadyqueued',
            '📋 <b>Already queued:</b> ' + fileName + '\n⏰ AI processing in progress. Use /today to check.');
        return;
    }

    // ── Gate 3: Date validation — accept today AND yesterday ──
    var fileNameDate = extractDateFromFilename(fileName);
    if (fileNameDate && fileNameDate !== today && fileNameDate !== yesterday) {
        cache.put(rejectedKey, '1', 86400); // Remember rejection for 24h
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_daterejected',
            '❌ <b>Skipped:</b> ' + fileName + '\n' +
            '📅 File date: ' + fileNameDate + ' | Today: ' + today + '\n' +
            '💡 Please send today\'s or yesterday\'s newspaper.');
        return;
    }

    // ── Gate 4: File size check (Telegram Bot API limit = 20 MB) ──
    if (fileSizeBytes > 20 * 1024 * 1024) {
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_toolarge',
            '⚠️ <b>Too large:</b> ' + fileName + ' (' + fileSizeMB + ' MB)\n' +
            '📂 Use web uploader: ' + getWebAppUrl());
        return;
    }

    // ── All checks passed — queue immediately (NO download in webhook — too slow for concurrent files) ──
    // We save a lightweight placeholder with the Telegram file_id.
    // processQueuedFiles will download the actual PDF when it processes the file.
    // This keeps the webhook handler fast (<5 sec) even with many files arriving at once.
    try {
        var newspaper = detectNewspaper(fileName);
        var config = getConfig();

        // Save a small placeholder to Drive with the file_id for later download
        var placeholderBlob = Utilities.newBlob('placeholder:' + telegramFileId, 'application/octet-stream', fileName);
        var driveFile = saveToDrive(placeholderBlob, fileName, config.DRIVE_FOLDER_ID);
        driveFile.setDescription('queued:' + chatId + ':fileid:' + telegramFileId);

        // Mark as queued to prevent duplicate queuing on re-send
        cache.put(queuedCacheKey, '1', 86400);

        // Send ONE combined message: Received + Queued (no separate "Received" then "Queued")
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_queued',
            '📥 <b>Received & Queued:</b> ' + fileName + ' (' + fileSizeMB + ' MB)\n' +
            '📰 ' + newspaper + '\n' +
            '⏰ AI processing starts within 1 min');

    } catch (procErr) {
        Logger.log('handleMessage error for ' + fileName + ': ' + procErr.message + '\n' + procErr.stack);
        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_queueerror',
            '❌ <b>Error queuing:</b> ' + fileName + '\n' +
            '🐛 ' + procErr.message + '\n' +
            '💡 Try sending the file again');
    }
}

function handleTextCommand(chatId, text) {
    var cmd = text.trim().toLowerCase();

    if (cmd === '/start' || cmd === '/help') {
        sendTelegramMessage(chatId,
            '🇮🇳 <b>UPSC Daily Edge — Content Pipeline</b>\n\n' +
            '📰 Send me newspaper PDFs and I will:\n' +
            '1. Save them to Google Drive\n' +
            '2. Extract articles using Gemini AI\n' +
            '3. Categorize for UPSC relevance\n' +
            '4. Push to your app automatically\n\n' +
            '📎 Supported newspapers:\n' +
            '• The Hindu (all editions)\n' +
            '• Indian Express\n' +
            '• The Hindu Business Line\n\n' +
            '� Accepts today\'s & yesterday\'s papers\n' +
            '�💡 <b>Bulk upload:</b> Send multiple PDFs at once — all will be processed!\n\n' +
            '<b>Commands:</b>\n' +
            '/status — Pipeline status + trigger health\n' +
            '/today — Articles processed today\n' +
            '/process — Force-process all unprocessed PDFs now\n' +
            '/upload — Upload link for large PDFs (>20 MB)\n' +
            '/keys — API key rotation status\n' +
            '/triggers — Check & fix trigger health\n' +
            '/debug — System diagnostics\n' +
            '/help — This message'
        );
    } else if (cmd === '/status') {
        var triggerCount = ScriptApp.getProjectTriggers().length;
        var triggerHealth = triggerCount <= 5 ? '✅ Healthy (' + triggerCount + ')' : '⚠️ High (' + triggerCount + ') — run /triggers to fix';
        var config2 = getConfig();
        var queuedCount = countQueuedFiles_(config2.DRIVE_FOLDER_ID);
        var articleCount = getTodayArticleCount();
        var statusMsg = '📊 <b>Pipeline Status</b>\n\n' +
            '⏱ Triggers: ' + triggerHealth + '\n' +
            '📋 Files in queue: ' + queuedCount + '\n' +
            '📝 Articles today: ' + articleCount + '\n' +
            '📅 Date: ' + getTodayIST();
        // Check for failed/stuck files
        try {
            var folder = DriveApp.getFolderById(config2.DRIVE_FOLDER_ID);
            var today2 = getTodayIST();
            var foldersToCheck = [folder];
            var dateFolders2 = folder.getFoldersByName(today2);
            if (dateFolders2.hasNext()) foldersToCheck.unshift(dateFolders2.next());
            var failedCount = 0, processingCount = 0;
            for (var sf = 0; sf < foldersToCheck.length; sf++) {
                var sFiles = foldersToCheck[sf].getFiles();
                while (sFiles.hasNext()) {
                    var sFile = sFiles.next();
                    if (!sFile.getName().toLowerCase().endsWith('.pdf')) continue;
                    var sDesc = sFile.getDescription() || '';
                    if (sDesc.indexOf('failed:') === 0) failedCount++;
                    if (sDesc.indexOf('processing:') === 0) processingCount++;
                }
            }
            if (failedCount > 0) statusMsg += '\n❌ Failed files: ' + failedCount + ' (use /process to retry)';
            if (processingCount > 0) statusMsg += '\n🔄 Currently processing: ' + processingCount;
        } catch (e) { /* ignore */ }
        sendTelegramMessage(chatId, statusMsg);
    } else if (cmd === '/today') {
        var count = getTodayArticleCount();
        sendTelegramMessage(chatId, '📊 <b>Today\'s Stats:</b>\n📝 Articles processed: ' + count);
    } else if (cmd === '/keys') {
        var keys = getGeminiKeys();
        var msg = '🔑 <b>API Key Rotation Status:</b>\n\n';
        msg += '📊 Total keys configured: <b>' + keys.length + '</b>\n';
        for (var i = 0; i < keys.length; i++) {
            var masked = keys[i].substring(0, 6) + '...' + keys[i].substring(keys[i].length - 4);
            msg += '  Key ' + (i + 1) + ': <code>' + masked + '</code>\n';
        }
        msg += '\n💡 Add more keys in Script Properties under GEMINI_API_KEYS (comma-separated).';
        sendTelegramMessage(chatId, msg);
    } else if (cmd === '/upload') {
        var uploadUrl = getWebAppUrl();
        sendTelegramMessage(chatId,
            '📂 <b>Web Uploader — No Size Limit</b>\n\n' +
            '🔗 ' + uploadUrl + '\n\n' +
            'Use this link to upload PDFs larger than 20 MB.\n' +
            'Files are saved to Google Drive and auto-processed within 1 minute.'
        );
    } else if (cmd === '/process') {
        sendTelegramMessage(chatId, '🔄 <b>Starting batch processing...</b>\nRe-queuing failed files + processing all queued PDFs...');
        try {
            // Re-queue failed files so they get picked up
            requeueFailedFiles_();
            processQueuedFiles();
            var processCount = getTodayArticleCount();
            sendTelegramMessage(chatId, '✅ <b>Batch processing complete!</b>\n📊 Total articles today: ' + processCount);
        } catch (processErr) {
            sendTelegramMessage(chatId, '❌ Processing error: ' + processErr.message);
        }
    } else if (cmd === '/triggers') {
        // Show trigger status and offer to fix
        var triggers = ScriptApp.getProjectTriggers();
        var lines = ['🔧 <b>Trigger Health Check</b>\n'];
        var queueCount = 0;
        var otherCount = 0;
        for (var t = 0; t < triggers.length; t++) {
            var fn = triggers[t].getHandlerFunction();
            if (fn === 'processQueuedFiles') queueCount++;
            else otherCount++;
            lines.push('  • ' + fn);
        }
        lines.push('\n📊 Total: ' + triggers.length + ' (queue: ' + queueCount + ', other: ' + otherCount + ')');
        if (triggers.length > 5) {
            lines.push('\n⚠️ Too many triggers! Running cleanup...');
            cleanupAllTriggers();
            setupTriggers();
            lines.push('✅ Fixed! Re-created clean triggers.');
        } else {
            lines.push('\n✅ Trigger count is healthy.');
        }
        sendTelegramMessage(chatId, lines.join('\n'));
    } else if (cmd === '/debug') {
        // Diagnostic command to check webhook and system health
        var config = getConfig();
        var webhookUrl = 'https://api.telegram.org/bot' + config.TELEGRAM_TOKEN + '/getWebhookInfo';
        try {
            var whResp = JSON.parse(UrlFetchApp.fetch(webhookUrl, { muteHttpExceptions: true }).getContentText());
            var whInfo = whResp.result || {};
            var keys = getGeminiKeys();
            var debugMsg = '🔍 <b>System Diagnostics</b>\n\n' +
                '🌐 <b>Webhook:</b>\n' +
                '  URL: ' + (whInfo.url ? '✅ Set' : '❌ Not set') + '\n' +
                '  Pending updates: ' + (whInfo.pending_update_count || 0) + '\n' +
                '  Last error: ' + (whInfo.last_error_message || 'None') + '\n' +
                '  Last error time: ' + (whInfo.last_error_date ? new Date(whInfo.last_error_date * 1000).toISOString() : 'N/A') + '\n\n' +
                '🔑 <b>Gemini Keys:</b> ' + keys.length + ' configured\n' +
                '📅 <b>Server time (IST):</b> ' + Utilities.formatDate(new Date(), IST_TIMEZONE, 'yyyy-MM-dd HH:mm:ss') + '\n' +
                '📂 <b>Drive folder:</b> ' + (config.DRIVE_FOLDER_ID ? '✅ Set' : '❌ Missing');
            sendTelegramMessage(chatId, debugMsg);
        } catch (debugErr) {
            sendTelegramMessage(chatId, '❌ Debug error: ' + debugErr.message);
        }
    } else {
        sendTelegramMessage(chatId, '📎 Send me a newspaper PDF to process!\nType /help for commands.');
    }
}

// ==========================================
//  TELEGRAM API
// ==========================================

function sendTelegramMessage(chatId, text) {
    var config = getConfig();
    var url = 'https://api.telegram.org/bot' + config.TELEGRAM_TOKEN + '/sendMessage';

    UrlFetchApp.fetch(url, {
        method: 'post',
        contentType: 'application/json',
        payload: JSON.stringify({
            chat_id: chatId,
            text: text,
            parse_mode: 'HTML'
        }),
        muteHttpExceptions: true
    });
}

function downloadTelegramFile(fileId) {
    try {
        var config = getConfig();

        // Step 1: Get file path from Telegram
        var infoUrl = 'https://api.telegram.org/bot' + config.TELEGRAM_TOKEN + '/getFile?file_id=' + fileId;
        var infoResp = JSON.parse(UrlFetchApp.fetch(infoUrl, { muteHttpExceptions: true }).getContentText());

        if (!infoResp.ok) {
            Logger.log('getFile failed: ' + JSON.stringify(infoResp));
            return null;
        }

        // Step 2: Download the file
        var filePath = infoResp.result.file_path;
        var downloadUrl = 'https://api.telegram.org/file/bot' + config.TELEGRAM_TOKEN + '/' + filePath;
        var response = UrlFetchApp.fetch(downloadUrl, { muteHttpExceptions: true });

        if (response.getResponseCode() !== 200) {
            Logger.log('File download failed: HTTP ' + response.getResponseCode());
            return null;
        }

        return response.getBlob();
    } catch (err) {
        Logger.log('downloadTelegramFile error: ' + err.message);
        return null;
    }
}

// ==========================================
//  GOOGLE DRIVE
// ==========================================

function saveToDrive(fileBlob, fileName, folderId) {
    var folder = DriveApp.getFolderById(folderId);

    // Create date subfolder (yyyy-MM-dd)
    var today = Utilities.formatDate(new Date(), IST_TIMEZONE, 'yyyy-MM-dd');
    var dateFolder;
    var existing = folder.getFoldersByName(today);
    if (existing.hasNext()) {
        dateFolder = existing.next();
    } else {
        dateFolder = folder.createFolder(today);
    }

    fileBlob.setName(fileName);
    var file = dateFolder.createFile(fileBlob);
    Logger.log('Saved to Drive: ' + file.getUrl());
    return file;
}

// ==========================================
//  NEWSPAPER DETECTION
// ==========================================

function detectNewspaper(fileName) {
    var name = fileName.toLowerCase();

    if (name.indexOf('business') !== -1 && name.indexOf('line') !== -1) return 'The Hindu Business Line';
    if (name.indexOf('hindu') !== -1 && name.indexOf('business') !== -1) return 'The Hindu Business Line';
    if (name.indexOf('hindu') !== -1 && name.indexOf('school') !== -1) return 'The Hindu School';
    if (name.indexOf('hindu') !== -1) return 'The Hindu';
    if (name.indexOf('indian express') !== -1 || name.indexOf('indianexpress') !== -1) return 'Indian Express';
    if (name.indexOf('express') !== -1) return 'Indian Express';

    // Short name detection — IE before TH so "IE" files aren't accidentally caught
    // Check IE first since "ie" is less ambiguous than "th"
    if (/^ie[\s_~.\-]/i.test(name) || /[\s_\-]ie[\s_~.\-]/i.test(name)) return 'Indian Express';

    // TH School before TH to avoid incorrect match
    if (/^th[\s_~.\-].*school/i.test(name) || name.indexOf('school') !== -1 && /^th[\s_~.\-]/i.test(name)) return 'The Hindu School';
    if (/^th[\s_~.\-]/i.test(name)) return 'The Hindu';

    Logger.log('detectNewspaper: could not detect newspaper from filename: ' + fileName);
    return 'Newspaper';
}

// ==========================================
//  GEMINI AI PROCESSING
// ==========================================

function processWithGemini(pdfBlob, newspaper, apiKey, chatId) {
    try {
        var pdfBytes = pdfBlob.getBytes();
        var base64Pdf = Utilities.base64Encode(pdfBytes);
        var today = Utilities.formatDate(new Date(), IST_TIMEZONE, 'yyyy-MM-dd');
        var fileSizeMB = (pdfBytes.length / (1024 * 1024)).toFixed(1);

        Logger.log('Processing PDF: ' + fileSizeMB + ' MB, base64: ' + (base64Pdf.length / (1024 * 1024)).toFixed(1) + ' MB');

        var prompt = 'You are an expert UPSC Civil Services Examination current affairs analyst with deep knowledge of the UPSC syllabus, previous year questions (2011-2025), government schemes, constitutional provisions, and editorial analysis.\n\n' +
            'Analyze this newspaper PDF (' + newspaper + ', Date: ' + today + ') and extract ALL important articles relevant to UPSC preparation.\n\n' +
            'For EACH article, provide:\n' +
            '1. title: Clear headline (max 100 chars)\n' +
            '2. summary: 3-4 sentence summary covering WHAT happened, WHY it matters, and UPSC relevance\n' +
            '3. content: Full detailed analysis (300-500 words) covering background context, current development, policy implications, and way forward with actionable suggestions\n' +
            '4. shortNotes: Exactly 5 bullet points for quick revision — each should be a standalone fact\n' +
            '5. keyPoints: 4-6 key takeaways that a UPSC aspirant must remember\n' +
            '6. examRelevance: "Prelims" or "Mains" or "Both"\n' +
            '7. upscPaper: "GS-I" or "GS-II" or "GS-III" or "GS-IV" or "Essay"\n' +
            '8. categoryTags: From ONLY: ["Polity","Economy","Environment","Science & Technology","International Relations","History","Geography","Social Issues","Governance","Security","Ethics"]\n' +
            '9. relatedTopics: 3-5 related UPSC topics from the official syllabus\n' +
            '10. analysisNote: 2-3 sentences on WHY this matters for UPSC and which angle to study\n' +
            '11. mnemonic: A catchy acronym, phrase, or memory trick to remember key facts. Empty string if not applicable.\n' +
            '12. isTopNews: true for front-page lead stories only\n' +
            '13. imageQuery: A specific Wikipedia article title for fetching a relevant image. Use EXACT Wikipedia page titles like institution names ("Reserve Bank of India", "Supreme Court of India"), person names ("Narendra Modi"), place names ("Ladakh"), organization names ("ISRO"), or scientific concepts ("Quantum computing"). Avoid generic terms like "economy" or "policy". Must be a real Wikipedia page title for best results.\n' +
            '14. flowchartSteps: Array of 3-6 short step labels showing cause-effect chain or process flow. Use arrows like "Step A" → "Step B" format. Empty array if not applicable.\n' +
            '15. syllabusMapping: Precise UPSC syllabus topic path (e.g. "GS-II > Polity > Parliament > Anti-Defection Law" or "GS-III > Economy > Monetary Policy > RBI Functions")\n' +
            '16. previousYearQs: Array of 1-3 related UPSC PYQ references with year and paper (e.g. ["2019 Prelims: Anti-Defection Law provisions", "2021 Mains GS-II: Role of Speaker in parliamentary democracy"]). Only cite questions you are confident about. Empty array if none.\n' +
            '17. editorialOpinion: 2-3 sentence summary of editorial viewpoint or expert analysis. Include the argument being made and the conclusion. Empty string if purely factual.\n' +
            '18. constitutionalBasis: Relevant Articles, Acts, or legal provisions with brief description (e.g. "Article 14, 15, 16 — Right to Equality; Article 21 — Right to Life"). Empty string if not applicable.\n' +
            '19. governmentScheme: Related government scheme with full name, launch year, and key features (e.g. "PM-KISAN (2019): Direct income support of Rs 6000/year to small & marginal farmer families, 3 installments"). Empty string if not applicable.\n' +
            '20. keyTerms: Object of 2-4 important terms with one-line definitions that a UPSC aspirant must know (e.g. {"CBDC":"Central Bank Digital Currency — digital form of fiat currency issued by RBI","SLR":"Statutory Liquidity Ratio — minimum govt securities banks must hold"}). Empty object if not applicable.\n' +
            '21. answerFramework: A brief Mains answer writing outline for this topic. Format: "Introduction: [1 line] | Body: [3-4 numbered points] | Conclusion: [1 line with way forward]". 4-6 lines total. Empty string if only Prelims relevant.\n' +
            '22. quizQuestions: Array of 3 MCQ quiz questions generated from this article. Each with: {"question":"...","options":["A","B","C","D"],"correctAnswerIndex":0,"explanation":"...","difficulty":"Easy|Medium|Hard"}. Questions must test conceptual understanding, not just recall. Include 1 Easy, 1 Medium, 1 Hard question.\n' +
            '23. flashcards: Array of 2 flashcards generated from this article. Each with: {"front":"Question or term","back":"Answer or definition (2-3 lines max)"}. Front should be a question that tests understanding.\n\n' +
            'QUALITY RULES:\n' +
            '- Extract 8-15 articles minimum from the newspaper\n' +
            '- Focus on governance, policy, economy, IR, environment, science, social issues, legal developments\n' +
            '- Skip entertainment, sports, advertisements, obituaries\n' +
            '- For previousYearQs, only cite actual UPSC CSE questions you are confident about\n' +
            '- For keyTerms, define technical/policy terms with precise one-line definitions\n' +
            '- quizQuestions MUST have exactly 4 options each, with plausible distractors\n' +
            '- Quiz explanations should teach WHY the answer is correct and WHY others are wrong\n' +
            '- flashcards should test the most exam-relevant concept from the article\n' +
            '- Ensure all options in quiz questions are of similar length and structure\n' +
            '- Avoid "All of the above" or "None of the above" options\n' +
            '- Content should be factually accurate and unbiased\n\n' +
            'Return ONLY a valid JSON object with this structure:\n' +
            '{"newspaper":"name","date":"' + today + '","articles":[{"title":"...","summary":"...","content":"...","shortNotes":["..."],"keyPoints":["..."],"examRelevance":"Both","upscPaper":"GS-II","categoryTags":["Polity"],"relatedTopics":["..."],"analysisNote":"...","mnemonic":"...","isTopNews":true,"imageQuery":"...","flowchartSteps":["..."],"syllabusMapping":"...","previousYearQs":["..."],"editorialOpinion":"...","constitutionalBasis":"...","governmentScheme":"...","keyTerms":{"term":"definition"},"answerFramework":"...","quizQuestions":[{"question":"...","options":["..."],"correctAnswerIndex":0,"explanation":"...","difficulty":"Medium"}],"flashcards":[{"front":"...","back":"..."}]}]}';

        // Try models in order — gemini-2.5-flash is best for PDFs
        var models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
        var lastError = '';

        for (var m = 0; m < models.length; m++) {
            var model = models[m];
            var url = 'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent?key=' + apiKey;

            var requestBody = {
                contents: [{
                    parts: [
                        { inline_data: { mime_type: 'application/pdf', data: base64Pdf } },
                        { text: prompt }
                    ]
                }],
                generationConfig: {
                    temperature: 0.3,
                    maxOutputTokens: 131072
                }
            };

            Logger.log('Trying model: ' + model);

            var response = UrlFetchApp.fetch(url, {
                method: 'post',
                contentType: 'application/json',
                payload: JSON.stringify(requestBody),
                muteHttpExceptions: true
            });

            var httpCode = response.getResponseCode();
            var responseText = response.getContentText();
            Logger.log('Model ' + model + ' HTTP ' + httpCode + ', response length: ' + responseText.length);

            if (httpCode !== 200) {
                lastError = model + ': HTTP ' + httpCode + ' - ' + responseText.substring(0, 300);
                Logger.log(lastError);
                continue; // Try next model
            }

            var responseData = JSON.parse(responseText);

            if (responseData.error) {
                lastError = model + ': ' + (responseData.error.message || JSON.stringify(responseData.error)).substring(0, 300);
                Logger.log('Gemini error: ' + lastError);
                continue; // Try next model
            }

            // Check for candidates
            if (!responseData.candidates || responseData.candidates.length === 0) {
                var blockReason = (responseData.promptFeedback && responseData.promptFeedback.blockReason) || 'no candidates returned';
                lastError = model + ': ' + blockReason;
                Logger.log('No candidates: ' + lastError);
                continue;
            }

            // Check finish reason
            var candidate = responseData.candidates[0];
            if (candidate.finishReason && candidate.finishReason !== 'STOP' && candidate.finishReason !== 'MAX_TOKENS') {
                lastError = model + ': finishReason=' + candidate.finishReason;
                Logger.log(lastError);
                continue;
            }

            if (!candidate.content || !candidate.content.parts || !candidate.content.parts[0].text) {
                lastError = model + ': Empty content in response';
                Logger.log(lastError);
                continue;
            }

            var textContent = candidate.content.parts[0].text;
            Logger.log('Got text response: ' + textContent.length + ' chars');

            // Strip markdown code fences if present
            var jsonStr = textContent.trim();
            if (jsonStr.substring(0, 3) === '```') {
                jsonStr = jsonStr.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
            }

            // Try to parse JSON
            var result;
            try {
                result = JSON.parse(jsonStr);
            } catch (parseErr) {
                // Try to find JSON in the text
                var jsonMatch = jsonStr.match(/\{[\s\S]*"articles"[\s\S]*\}/);
                if (jsonMatch) {
                    try {
                        result = JSON.parse(jsonMatch[0]);
                    } catch (e) {
                        lastError = model + ': JSON parse failed - ' + parseErr.message + ' | First 200 chars: ' + jsonStr.substring(0, 200);
                        Logger.log(lastError);
                        continue;
                    }
                } else {
                    lastError = model + ': No JSON found in response. First 200 chars: ' + jsonStr.substring(0, 200);
                    Logger.log(lastError);
                    continue;
                }
            }

            if (!result.articles || result.articles.length === 0) {
                lastError = model + ': JSON parsed but no articles array found';
                Logger.log(lastError);
                continue;
            }

            // Add metadata and fetch images for each article
            var articles = result.articles.map(function(article, index) {
                article.newspaper = result.newspaper || newspaper;
                article.publishedDate = result.date || today;
                // ID assigned later in processQueuedFiles with file hash for uniqueness
                article.id = today.replace(/-/g, '') + '_' + newspaper.replace(/\s+/g, '_').toLowerCase() + '_' + (index + 1);
                // Generate source URL for linking to original newspaper article
                article.sourceUrl = getNewspaperSearchUrl(article.newspaper, article.title);
                // Fetch image from Wikipedia based on imageQuery
                if (article.imageQuery) {
                    article.imageUrl = fetchWikipediaImage(article.imageQuery) || '';
                } else {
                    article.imageUrl = '';
                }
                // Ensure all array/object fields exist
                article.flowchartSteps = article.flowchartSteps || [];
                article.previousYearQs = article.previousYearQs || [];
                article.keyTerms = article.keyTerms || {};
                article.syllabusMapping = article.syllabusMapping || '';
                article.editorialOpinion = article.editorialOpinion || '';
                article.constitutionalBasis = article.constitutionalBasis || '';
                article.governmentScheme = article.governmentScheme || '';
                article.answerFramework = article.answerFramework || '';
                article.quizQuestions = article.quizQuestions || [];
                article.flashcards = article.flashcards || [];

                // Validate and fix quiz questions
                article.quizQuestions = article.quizQuestions.filter(function(q) {
                    if (!q.question || !q.options || q.options.length !== 4) return false;
                    if (typeof q.correctAnswerIndex !== 'number' || q.correctAnswerIndex < 0 || q.correctAnswerIndex > 3) return false;
                    q.explanation = q.explanation || '';
                    q.difficulty = (['Easy', 'Medium', 'Hard'].indexOf(q.difficulty) >= 0) ? q.difficulty : 'Medium';
                    return true;
                });

                // Validate flashcards
                article.flashcards = article.flashcards.filter(function(fc) {
                    return fc.front && fc.back && fc.front.length > 0 && fc.back.length > 0;
                });

                return article;
            });

            Logger.log('SUCCESS: Extracted ' + articles.length + ' articles from ' + newspaper + ' using ' + model);
            return { articles: articles, error: null };
        }

        // All models failed
        Logger.log('ALL MODELS FAILED. Last error: ' + lastError);
        return { articles: null, error: lastError };

    } catch (err) {
        Logger.log('Gemini processing error: ' + err.message + '\n' + err.stack);
        return { articles: null, error: err.message };
    }
}

// ==========================================
//  IMAGE FETCHING (Wikipedia API — free, no key)
// ==========================================

// Generate a search URL on the newspaper's website for the article
function getNewspaperSearchUrl(newspaper, articleTitle) {
    var q = encodeURIComponent(articleTitle || '');
    switch (newspaper) {
        case 'The Hindu':
            return 'https://www.thehindu.com/search/?q=' + q;
        case 'Indian Express':
            return 'https://indianexpress.com/?s=' + q;
        case 'The Hindu Business Line':
            return 'https://www.thehindubusinessline.com/search/?q=' + q;
        case 'The Hindu School':
            return 'https://www.thehindu.com/education/';
        default:
            return '';
    }
}

function fetchWikipediaImage(query) {
    if (!query || query.trim().length === 0) return '';

    try {
        // Strategy 1: Direct Wikipedia page title lookup
        var directUrl = 'https://en.wikipedia.org/w/api.php?action=query&titles=' +
            encodeURIComponent(query) +
            '&prop=pageimages&format=json&pithumbsize=800&redirects=1';

        var resp = UrlFetchApp.fetch(directUrl, { muteHttpExceptions: true });
        if (resp.getResponseCode() === 200) {
            var data = JSON.parse(resp.getContentText());
            var pages = data.query && data.query.pages;
            if (pages) {
                var pageIds = Object.keys(pages);
                for (var i = 0; i < pageIds.length; i++) {
                    var page = pages[pageIds[i]];
                    if (page.thumbnail && page.thumbnail.source) {
                        return page.thumbnail.source;
                    }
                }
            }
        }

        // Strategy 2: Search Wikipedia and get image from top results
        var searchUrl = 'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=' +
            encodeURIComponent(query) +
            '&format=json&srlimit=5';
        var resp2 = UrlFetchApp.fetch(searchUrl, { muteHttpExceptions: true });
        if (resp2.getResponseCode() === 200) {
            var data2 = JSON.parse(resp2.getContentText());
            var results = data2.query && data2.query.search;
            if (results && results.length > 0) {
                // Try each search result until we find one with an image
                for (var r = 0; r < Math.min(results.length, 3); r++) {
                    var pageTitle = results[r].title;
                    var imgUrl = 'https://en.wikipedia.org/w/api.php?action=query&titles=' +
                        encodeURIComponent(pageTitle) +
                        '&prop=pageimages&format=json&pithumbsize=800&redirects=1';
                    var resp3 = UrlFetchApp.fetch(imgUrl, { muteHttpExceptions: true });
                    if (resp3.getResponseCode() === 200) {
                        var data3 = JSON.parse(resp3.getContentText());
                        var pages3 = data3.query && data3.query.pages;
                        if (pages3) {
                            var ids3 = Object.keys(pages3);
                            for (var j = 0; j < ids3.length; j++) {
                                var p = pages3[ids3[j]];
                                if (p.thumbnail && p.thumbnail.source) {
                                    return p.thumbnail.source;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Strategy 3: Wikimedia Commons search — has more images than Wikipedia articles
        var commonsUrl = 'https://commons.wikimedia.org/w/api.php?action=query&list=search' +
            '&srnamespace=6&srsearch=' + encodeURIComponent(query) +
            '&format=json&srlimit=3';
        var resp4 = UrlFetchApp.fetch(commonsUrl, { muteHttpExceptions: true });
        if (resp4.getResponseCode() === 200) {
            var data4 = JSON.parse(resp4.getContentText());
            var commonsResults = data4.query && data4.query.search;
            if (commonsResults && commonsResults.length > 0) {
                var commonsTitle = commonsResults[0].title;
                var commonsImgUrl = 'https://commons.wikimedia.org/w/api.php?action=query&titles=' +
                    encodeURIComponent(commonsTitle) +
                    '&prop=imageinfo&iiprop=url|size&iiurlwidth=800&format=json';
                var resp5 = UrlFetchApp.fetch(commonsImgUrl, { muteHttpExceptions: true });
                if (resp5.getResponseCode() === 200) {
                    var data5 = JSON.parse(resp5.getContentText());
                    var commonsPages = data5.query && data5.query.pages;
                    if (commonsPages) {
                        var commonsIds = Object.keys(commonsPages);
                        for (var c = 0; c < commonsIds.length; c++) {
                            var cp = commonsPages[commonsIds[c]];
                            if (cp.imageinfo && cp.imageinfo[0]) {
                                // Prefer the resized thumbnail URL, fall back to original
                                return cp.imageinfo[0].thumburl || cp.imageinfo[0].url || '';
                            }
                        }
                    }
                }
            }
        }

        return '';
    } catch (err) {
        Logger.log('Wikipedia image fetch error: ' + err.message);
        return '';
    }
}

// ==========================================
//  FIRESTORE (via REST API + Service Account JWT)
// ==========================================

function getFirebaseAccessToken(config) {
    var sa = config.SERVICE_ACCOUNT;

    var header = { alg: 'RS256', typ: 'JWT' };
    var now = Math.floor(Date.now() / 1000);

    var claimSet = {
        iss: sa.client_email,
        scope: 'https://www.googleapis.com/auth/datastore',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600
    };

    var encodedHeader = Utilities.base64EncodeWebSafe(JSON.stringify(header));
    var encodedClaims = Utilities.base64EncodeWebSafe(JSON.stringify(claimSet));
    var signatureInput = encodedHeader + '.' + encodedClaims;

    var signatureBytes = Utilities.computeRsaSha256Signature(signatureInput, sa.private_key);
    var encodedSignature = Utilities.base64EncodeWebSafe(signatureBytes);

    var jwt = signatureInput + '.' + encodedSignature;

    var tokenResp = UrlFetchApp.fetch('https://oauth2.googleapis.com/token', {
        method: 'post',
        contentType: 'application/x-www-form-urlencoded',
        payload: 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' + jwt,
        muteHttpExceptions: true
    });

    var tokenData = JSON.parse(tokenResp.getContentText());
    if (tokenData.error) {
        Logger.log('Token error: ' + JSON.stringify(tokenData));
        return null;
    }

    return tokenData.access_token;
}

function writeToFirestore(articles, config) {
    var accessToken = getFirebaseAccessToken(config);
    if (!accessToken) {
        Logger.log('Failed to get Firebase access token');
        return 0;
    }

    var projectId = config.PROJECT_ID;
    var baseUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents';

    var successCount = 0;
    var quizCount = 0;
    var flashcardCount = 0;

    for (var i = 0; i < articles.length; i++) {
        var article = articles[i];
        try {
            var docId = article.id;
            var url = baseUrl + '/articles/' + docId;

            // Build keyTerms as a Firestore map
            var keyTermsFields = {};
            var kt = article.keyTerms || {};
            var ktKeys = Object.keys(kt);
            for (var k = 0; k < ktKeys.length; k++) {
                keyTermsFields[ktKeys[k]] = { stringValue: kt[ktKeys[k]] || '' };
            }

            var firestoreDoc = {
                fields: {
                    title: { stringValue: article.title || '' },
                    summary: { stringValue: article.summary || '' },
                    content: { stringValue: article.content || '' },
                    shortNotes: { arrayValue: { values: (article.shortNotes || []).map(function(s) { return { stringValue: s }; }) } },
                    keyPoints: { arrayValue: { values: (article.keyPoints || []).map(function(s) { return { stringValue: s }; }) } },
                    examRelevance: { stringValue: article.examRelevance || 'Both' },
                    upscPaper: { stringValue: article.upscPaper || '' },
                    categoryTags: { arrayValue: { values: (article.categoryTags || []).map(function(s) { return { stringValue: s }; }) } },
                    relatedTopics: { arrayValue: { values: (article.relatedTopics || []).map(function(s) { return { stringValue: s }; }) } },
                    analysisNote: { stringValue: article.analysisNote || '' },
                    mnemonic: { stringValue: article.mnemonic || '' },
                    newspaper: { stringValue: article.newspaper || '' },
                    imageUrl: { stringValue: article.imageUrl || '' },
                    publishedDate: { stringValue: article.publishedDate || '' },
                    isTopNews: { booleanValue: article.isTopNews === true },
                    flowchartSteps: { arrayValue: { values: (article.flowchartSteps || []).map(function(s) { return { stringValue: s }; }) } },
                    syllabusMapping: { stringValue: article.syllabusMapping || '' },
                    previousYearQs: { arrayValue: { values: (article.previousYearQs || []).map(function(s) { return { stringValue: s }; }) } },
                    editorialOpinion: { stringValue: article.editorialOpinion || '' },
                    constitutionalBasis: { stringValue: article.constitutionalBasis || '' },
                    governmentScheme: { stringValue: article.governmentScheme || '' },
                    sourceUrl: { stringValue: article.sourceUrl || '' },
                    keyTerms: { mapValue: { fields: keyTermsFields } },
                    answerFramework: { stringValue: article.answerFramework || '' },
                    createdAt: { timestampValue: new Date().toISOString() }
                }
            };

            var resp = UrlFetchApp.fetch(url, {
                method: 'patch',
                contentType: 'application/json',
                headers: { 'Authorization': 'Bearer ' + accessToken },
                payload: JSON.stringify(firestoreDoc),
                muteHttpExceptions: true
            });

            if (resp.getResponseCode() === 200) {
                successCount++;

                // Write quiz questions generated from this article
                if (article.quizQuestions && article.quizQuestions.length > 0) {
                    for (var q = 0; q < article.quizQuestions.length; q++) {
                        var quiz = article.quizQuestions[q];
                        var qDocId = docId + '_q' + (q + 1);
                        try {
                            var qUrl = baseUrl + '/quizQuestions/' + qDocId;
                            var qDoc = {
                                fields: {
                                    question: { stringValue: quiz.question || '' },
                                    options: { arrayValue: { values: (quiz.options || []).map(function(o) { return { stringValue: o }; }) } },
                                    correctAnswerIndex: { integerValue: String(quiz.correctAnswerIndex || 0) },
                                    explanation: { stringValue: quiz.explanation || '' },
                                    category: { stringValue: (article.categoryTags && article.categoryTags[0]) || '' },
                                    difficulty: { stringValue: quiz.difficulty || 'Medium' },
                                    articleRef: { stringValue: docId },
                                    pyqYear: { stringValue: '' },
                                    syllabusArea: { stringValue: article.syllabusMapping || '' },
                                    source: { stringValue: 'daily_news' },
                                    publishedDate: { stringValue: article.publishedDate || '' },
                                    createdAt: { timestampValue: new Date().toISOString() }
                                }
                            };
                            var qResp = UrlFetchApp.fetch(qUrl, {
                                method: 'patch',
                                contentType: 'application/json',
                                headers: { 'Authorization': 'Bearer ' + accessToken },
                                payload: JSON.stringify(qDoc),
                                muteHttpExceptions: true
                            });
                            if (qResp.getResponseCode() === 200) quizCount++;
                        } catch (qErr) {
                            Logger.log('Quiz write error for ' + qDocId + ': ' + qErr.message);
                        }
                    }
                }

                // Write flashcards generated from this article
                if (article.flashcards && article.flashcards.length > 0) {
                    for (var f = 0; f < article.flashcards.length; f++) {
                        var card = article.flashcards[f];
                        var fDocId = docId + '_fc' + (f + 1);
                        try {
                            var fUrl = baseUrl + '/flashcards/' + fDocId;
                            var fDoc = {
                                fields: {
                                    front: { stringValue: card.front || '' },
                                    back: { stringValue: card.back || '' },
                                    category: { stringValue: (article.categoryTags && article.categoryTags[0]) || '' },
                                    articleRef: { stringValue: docId },
                                    publishedDate: { stringValue: article.publishedDate || '' },
                                    createdAt: { timestampValue: new Date().toISOString() }
                                }
                            };
                            var fResp = UrlFetchApp.fetch(fUrl, {
                                method: 'patch',
                                contentType: 'application/json',
                                headers: { 'Authorization': 'Bearer ' + accessToken },
                                payload: JSON.stringify(fDoc),
                                muteHttpExceptions: true
                            });
                            if (fResp.getResponseCode() === 200) flashcardCount++;
                        } catch (fErr) {
                            Logger.log('Flashcard write error for ' + fDocId + ': ' + fErr.message);
                        }
                    }
                }
            } else {
                Logger.log('Firestore write failed for ' + docId + ': ' + resp.getContentText());
            }
        } catch (err) {
            Logger.log('Write error for article ' + i + ': ' + err.message);
        }
    }

    Logger.log('Wrote ' + successCount + '/' + articles.length + ' articles, ' + quizCount + ' quiz questions, ' + flashcardCount + ' flashcards to Firestore');
    return successCount;
}

function getTodayArticleCount() {
    try {
        var config = getConfig();
        var accessToken = getFirebaseAccessToken(config);
        if (!accessToken) return 0;

        var today = Utilities.formatDate(new Date(), IST_TIMEZONE, 'yyyy-MM-dd');
        var url = 'https://firestore.googleapis.com/v1/projects/' + config.PROJECT_ID +
            '/databases/(default)/documents:runQuery';

        var body = {
            structuredQuery: {
                from: [{ collectionId: 'articles' }],
                where: {
                    fieldFilter: {
                        field: { fieldPath: 'publishedDate' },
                        op: 'EQUAL',
                        value: { stringValue: today }
                    }
                },
                select: { fields: [{ fieldPath: '__name__' }] }
            }
        };

        var resp = UrlFetchApp.fetch(url, {
            method: 'post',
            contentType: 'application/json',
            headers: { 'Authorization': 'Bearer ' + accessToken },
            payload: JSON.stringify(body),
            muteHttpExceptions: true
        });

        var results = JSON.parse(resp.getContentText());
        if (Array.isArray(results)) {
            return results.filter(function(r) { return r.document; }).length;
        }
        return 0;
    } catch (err) {
        return 0;
    }
}

// ==========================================
//  QUEUE PROCESSING (runs every 1 min via recurring trigger)
//  Processes ALL queued files one by one sequentially.
//  Each file gets: 1 "Processing" msg, 1 "Done"/"Failed" msg. No spam.
//  Retries failed files up to 3 times silently (only notifies on final success/failure).
//  Uses LockService to prevent concurrent executions (avoids race conditions).
// ==========================================
function processQueuedFiles() {
    // Acquire script-wide lock: only ONE execution at a time
    var lock = LockService.getScriptLock();
    var hasLock = lock.tryLock(5000); // Wait up to 5 seconds
    if (!hasLock) {
        Logger.log('processQueuedFiles: Another instance is running. Skipping this trigger cycle.');
        return;
    }

    try {
    _processQueuedFilesInternal();
    } finally {
        lock.releaseLock();
    }
}

// Internal: actual queue processing logic (called under lock)
function _processQueuedFilesInternal() {
    var config = getConfig();
    var folder = DriveApp.getFolderById(config.DRIVE_FOLDER_ID);
    var today = getTodayIST();
    var yesterday = getYesterdayIST();
    var startTime = Date.now();
    var MAX_EXECUTION_MS = 300000; // 5 min budget (Apps Script limit is 6 min)
    var PER_FILE_BUDGET_MS = 240000; // 4 min max per file — ensures others get processed
    var QUOTA_COOLDOWN_MS = 65000; // 65 sec cooldown when quota is exhausted
    var MAX_RETRIES = 3;
    var STUCK_THRESHOLD_MS = 300000; // 5 min

    // Check if we're in a Gemini quota cooldown period
    var cache = CacheService.getScriptCache();
    var cooldownUntil = cache.get('gemini_quota_cooldown');
    if (cooldownUntil) {
        var cooldownRemaining = parseInt(cooldownUntil, 10) - Date.now();
        if (cooldownRemaining > 0) {
            Logger.log('Gemini quota cooldown active. Waiting ' + Math.round(cooldownRemaining / 1000) + 's. Skipping this cycle.');
            return;
        }
        // Cooldown expired, clear it
        cache.remove('gemini_quota_cooldown');
        Logger.log('Gemini quota cooldown expired. Resuming processing.');
    }

    // Look in today's date subfolder + yesterday's + root
    var foldersToCheck = [folder];
    var dateFolders = folder.getFoldersByName(today);
    if (dateFolders.hasNext()) foldersToCheck.unshift(dateFolders.next());
    var yesterdayFolders = folder.getFoldersByName(yesterday);
    if (yesterdayFolders.hasNext()) foldersToCheck.unshift(yesterdayFolders.next());

    // Phase 0: Detect stuck "processing:" files and re-queue them (silently)
    for (var sf = 0; sf < foldersToCheck.length; sf++) {
        var stuckFiles = foldersToCheck[sf].getFiles();
        while (stuckFiles.hasNext()) {
            var stuckFile = stuckFiles.next();
            if (!stuckFile.getName().toLowerCase().endsWith('.pdf')) continue;
            var stuckDesc = stuckFile.getDescription() || '';
            if (stuckDesc.indexOf('processing:') === 0) {
                var lastUpdated = stuckFile.getLastUpdated();
                var stuckMs = Date.now() - lastUpdated.getTime();
                if (stuckMs > STUCK_THRESHOLD_MS) {
                    // Preserve file_id when re-queuing stuck files
                    var stuckPayload = stuckDesc.substring('processing:'.length);
                    var stuckFidMatch = stuckPayload.match(/:fileid:(.+)$/);
                    var stuckChatId = stuckFidMatch ? stuckPayload.substring(0, stuckPayload.indexOf(':fileid:')) : stuckPayload;
                    var stuckFidSuffix = stuckFidMatch ? ':fileid:' + stuckFidMatch[1] : '';
                    stuckFile.setDescription('retry:1:' + stuckChatId + stuckFidSuffix);
                    Logger.log('Re-queued stuck file: ' + stuckFile.getName() + ' (stuck ' + Math.round(stuckMs / 1000) + 's)');
                    // No Telegram message for stuck re-queue — silent retry
                }
            }
        }
    }

    // Phase 0.5: Auto-queue PDFs uploaded directly to Drive (no description)
    // This allows skipping Telegram entirely — just drop PDFs into the Drive folder
    for (var af = 0; af < foldersToCheck.length; af++) {
        var autoFiles = foldersToCheck[af].getFiles();
        while (autoFiles.hasNext()) {
            var autoFile = autoFiles.next();
            if (!autoFile.getName().toLowerCase().endsWith('.pdf')) continue;
            var autoDesc = autoFile.getDescription() || '';
            // No description = freshly uploaded via Drive UI (not from Telegram or web form)
            if (autoDesc === '') {
                autoFile.setDescription('queued:drive');
                Logger.log('Auto-queued Drive upload: ' + autoFile.getName());
            }
        }
    }

    // Phase 1: Collect ALL queued/retry files
    // NOTE: Queued/retry files expire at end of day — if a file was queued on a
    // previous day and still not processed, it's marked expired and skipped.
    // Users must re-send the file for the new day.
    var queuedFiles = [];
    var expiredCount = 0;
    for (var f = 0; f < foldersToCheck.length; f++) {
        var currentFolder = foldersToCheck[f];
        var files = currentFolder.getFiles();
        while (files.hasNext()) {
            var file = files.next();
            var fileName = file.getName();
            if (!fileName.toLowerCase().endsWith('.pdf')) continue;
            var desc = file.getDescription() || '';
            if (desc.indexOf('queued:') === 0 || desc.indexOf('retry:') === 0) {
                // Expire queued/retry files from previous days
                var fileCreatedDate = Utilities.formatDate(file.getDateCreated(), IST_TIMEZONE, 'yyyy-MM-dd');
                if (fileCreatedDate < today) {
                    file.setDescription('expired:' + today + ':queued_from_' + fileCreatedDate);
                    expiredCount++;
                    Logger.log('Expired stale queued file: ' + fileName + ' (queued on ' + fileCreatedDate + ', today is ' + today + ')');
                    // Notify user that their file expired
                    var expChatId = null;
                    if (desc.indexOf('queued:') === 0) {
                        var expPart = desc.substring('queued:'.length);
                        var expFidMatch = expPart.match(/:fileid:.+$/);
                        expChatId = expFidMatch ? expPart.substring(0, expPart.indexOf(':fileid:')) : expPart;
                    } else if (desc.indexOf('retry:') === 0) {
                        var expRetryPart = desc.substring('retry:'.length);
                        var expRetryCountEnd = expRetryPart.indexOf(':');
                        var expRemaining = expRetryPart.substring(expRetryCountEnd + 1);
                        var expFidMatch2 = expRemaining.match(/:fileid:.+$/);
                        expChatId = expFidMatch2 ? expRemaining.substring(0, expRemaining.indexOf(':fileid:')) : expRemaining;
                    }
                    if (expChatId && expChatId !== 'web' && expChatId !== 'drive') {
                        sendTelegramMessageOnce(expChatId, expChatId + '_expired_' + fileName + '_' + fileCreatedDate,
                            '⏰ <b>Expired:</b> ' + fileName + '\n' +
                            '📅 Queued on ' + fileCreatedDate + ' but not processed before day ended.\n' +
                            '💡 Please re-send today\'s newspaper.');
                    }
                    continue; // Skip this file — don't add to queue
                }
                var chatId, retryCount = 0, telegramFileId = null;
                if (desc.indexOf('retry:') === 0) {
                    var retryParts = desc.substring('retry:'.length);
                    var retryCountEnd = retryParts.indexOf(':');
                    retryCount = parseInt(retryParts.substring(0, retryCountEnd), 10) || 0;
                    var remaining = retryParts.substring(retryCountEnd + 1);
                    var fidMatch = remaining.match(/:fileid:(.+)$/);
                    if (fidMatch) {
                        telegramFileId = fidMatch[1];
                        chatId = remaining.substring(0, remaining.indexOf(':fileid:'));
                    } else {
                        chatId = remaining;
                    }
                } else {
                    var queuedPart = desc.substring('queued:'.length);
                    var fidMatch2 = queuedPart.match(/:fileid:(.+)$/);
                    if (fidMatch2) {
                        telegramFileId = fidMatch2[1];
                        chatId = queuedPart.substring(0, queuedPart.indexOf(':fileid:'));
                    } else {
                        chatId = queuedPart;
                    }
                }
                queuedFiles.push({ file: file, fileName: fileName, chatId: chatId, retryCount: retryCount, telegramFileId: telegramFileId });
            }
        }
    }

    if (expiredCount > 0) {
        Logger.log('Expired ' + expiredCount + ' stale queued file(s) from previous day(s)');
    }

    if (queuedFiles.length === 0) return;

    var totalFiles = queuedFiles.length;
    var processedCount = 0;
    var filesProcessed = 0;
    var filesFailed = 0;

    Logger.log('Queue found ' + totalFiles + ' file(s) to process');

    // Phase 2: Process each file one by one sequentially
    // Message strategy per file:
    //   First attempt: 1 "Processing" msg → 1 "Done" or 1 "Retrying" msg
    //   Retries: NO "Processing" msg → silent retry → 1 "Done" or 1 "Failed" msg at final attempt
    for (var q = 0; q < queuedFiles.length; q++) {
        var elapsedTotal = Date.now() - startTime;
        // Skip if not enough time left for another file (need at least 60s headroom)
        if (elapsedTotal > MAX_EXECUTION_MS) {
            Logger.log('Time budget exceeded. ' + (totalFiles - q) + ' files deferred to next cycle.');
            var deferChatId = queuedFiles[q].chatId;
            if (deferChatId && deferChatId !== 'web') {
                sendTelegramMessageOnce(deferChatId, deferChatId + '_timelimit_' + today,
                    '⏸ <b>Time limit reached</b>\n' +
                    '📄 Processed ' + filesProcessed + '/' + totalFiles + ' files\n' +
                    '⏰ Remaining ' + (totalFiles - q) + ' file(s) continue in ~1 min');
            }
            break;
        }

        var qf = queuedFiles[q];
        var file = qf.file;
        var fileName = qf.fileName;
        var chatId = qf.chatId;
        var retryCount = qf.retryCount;
        var telegramFileId = qf.telegramFileId;
        var isWebUpload = (chatId === 'web' || chatId === 'drive');
        var editionKey = buildEditionKey(fileName);
        var fileNum = q + 1;
        var progressLabel = '(' + fileNum + '/' + totalFiles + ')';

        try {
            var fileIdSuffix = telegramFileId ? ':fileid:' + telegramFileId : '';
            file.setDescription('processing:' + chatId + fileIdSuffix);
            Logger.log('Processing ' + progressLabel + ': ' + fileName + ' (retry: ' + retryCount + ')');
            var fileStartTime = Date.now();

            var newspaper = detectNewspaper(fileName);

            // Send "Processing" notification ONLY on first attempt (retries are silent)
            if (!isWebUpload && retryCount === 0) {
                sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_processing',
                    '🤖 <b>Processing ' + progressLabel + ':</b> ' + fileName + '\n' +
                    '📰 ' + newspaper + '\n' +
                    '🔄 Running Gemini AI... (30-90 sec)');
            }

            // Get the actual PDF blob — download from Telegram since webhook only saves placeholder
            var blob = file.getBlob();
            var blobBytes = blob.getBytes();
            // Fallback: extract file_id from placeholder blob content if not in description
            if (!telegramFileId && blobBytes.length < 1000) {
                var blobContent = blob.getDataAsString();
                var placeholderMatch = blobContent.match(/^placeholder:(.+)$/);
                if (placeholderMatch) {
                    telegramFileId = placeholderMatch[1];
                    Logger.log('Recovered file_id from placeholder blob content');
                }
            }
            if (blobBytes.length < 1000 && telegramFileId) {
                Logger.log('Downloading PDF from Telegram: ' + fileName + ' (file_id: ' + telegramFileId.substring(0, 20) + '...)');
                var downloadedBlob = downloadTelegramFile(telegramFileId);
                if (downloadedBlob) {
                    blob = downloadedBlob;
                } else {
                    throw new Error('Telegram download failed (file may have expired). Please re-send.');
                }
            } else if (blobBytes.length < 1000 && !telegramFileId) {
                throw new Error('No PDF content and no Telegram file_id to download from. Please re-send.');
            }

            var geminiResult = processWithGeminiRotation(blob, newspaper, isWebUpload ? null : chatId);

            // Per-file time check: if this file took longer than PER_FILE_BUDGET_MS, log it
            var fileElapsed = Date.now() - fileStartTime;
            if (fileElapsed > PER_FILE_BUDGET_MS) {
                Logger.log('WARNING: File ' + fileName + ' took ' + Math.round(fileElapsed / 1000) + 's (over ' + Math.round(PER_FILE_BUDGET_MS / 1000) + 's budget)');
            }

            // QUOTA EXHAUSTION: All Gemini keys hit rate limits — enter cooldown
            if (geminiResult && geminiResult.isQuotaExhausted) {
                Logger.log('QUOTA EXHAUSTED: Entering cooldown for ' + Math.round(QUOTA_COOLDOWN_MS / 1000) + 's');
                var cooldownExpiry = Date.now() + QUOTA_COOLDOWN_MS;
                CacheService.getScriptCache().put('gemini_quota_cooldown', String(cooldownExpiry), Math.ceil(QUOTA_COOLDOWN_MS / 1000) + 10);
                // Re-queue this file for retry after cooldown — DON'T count as a failure attempt
                file.setDescription('retry:' + retryCount + ':' + chatId + (telegramFileId ? ':fileid:' + telegramFileId : ''));
                if (!isWebUpload) {
                    sendTelegramMessageOnce(chatId, chatId + '_quota_wait_' + today + '_' + q,
                        '⏸ <b>AI quota limit reached</b>\n' +
                        '📄 ' + fileName + ' ' + progressLabel + '\n' +
                        '⏳ Pausing for ~' + Math.round(QUOTA_COOLDOWN_MS / 1000) + 's, then auto-resume\n' +
                        '📝 Remaining files: ' + (totalFiles - q) + ' — nothing will be lost');
                }
                break; // Stop processing more files — next trigger cycle will resume after cooldown
            }

            if (geminiResult && geminiResult.articles && geminiResult.articles.length > 0) {
                // SUCCESS — Assign unique IDs
                var fileHash = shortHash(fileName + '_' + file.getId());
                for (var i = 0; i < geminiResult.articles.length; i++) {
                    geminiResult.articles[i].id = today.replace(/-/g, '') + '_' +
                        newspaper.replace(/\s+/g, '_').toLowerCase() + '_' + fileHash + '_' + (i + 1);
                }

                writeToFirestore(geminiResult.articles, config);
                var elapsed = Math.round((Date.now() - fileStartTime) / 1000);
                processedCount += geminiResult.articles.length;
                filesProcessed++;

                CacheService.getScriptCache().put('processed_ok_' + today + '_' + editionKey, '1', 86400);

                // Clean up the PDF from Drive
                try {
                    file.setTrashed(true);
                } catch (delErr) {
                    file.setDescription('done:' + today + ':' + geminiResult.articles.length + 'articles');
                }

                // ONE success message per file (deduped so retries that succeed don't double-notify)
                if (!isWebUpload) {
                    sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_done',
                        '✅ <b>Done ' + progressLabel + ':</b> ' + fileName + '\n' +
                        '📰 ' + newspaper + '\n' +
                        '📊 ' + geminiResult.articles.length + ' articles extracted\n' +
                        '⏱ ' + elapsed + 's' +
                        (retryCount > 0 ? ' (succeeded on retry ' + retryCount + ')' : '') +
                        (fileNum < totalFiles ? '\n\n⏳ Processing next file...' : ''));
                }
            } else {
                // FAILED — retry or give up
                var newRetry = retryCount + 1;
                var retryFileIdSuffix = telegramFileId ? ':fileid:' + telegramFileId : '';
                var errorMsg = (geminiResult && geminiResult.error) || 'Unknown error';

                if (newRetry < MAX_RETRIES) {
                    // Silent retry — NO notification to user (will retry next trigger cycle)
                    file.setDescription('retry:' + newRetry + ':' + chatId + retryFileIdSuffix);
                    Logger.log('File ' + fileName + ' failed, silent retry ' + newRetry + '/' + MAX_RETRIES + ': ' + errorMsg);
                    filesFailed++;
                } else {
                    // Final failure — send ONE failure notification
                    file.setDescription('failed:' + today + ':' + errorMsg.substring(0, 100));
                    filesFailed++;
                    if (!isWebUpload) {
                        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_failed',
                            '❌ <b>Failed ' + progressLabel + ':</b> ' + fileName + '\n' +
                            '🔄 All ' + MAX_RETRIES + ' attempts exhausted\n' +
                            '❌ ' + errorMsg + '\n' +
                            '💾 Use /process to retry or send the file again');
                    }
                }
            }
        } catch (fileErr) {
            Logger.log('Queue error for ' + fileName + ': ' + fileErr.message);
            try {
                // Check if this exception is a quota/rate limit error
                var errMsg = fileErr.message.toLowerCase();
                var isQuotaErr = errMsg.indexOf('429') !== -1 || errMsg.indexOf('quota') !== -1 ||
                    errMsg.indexOf('rate') !== -1 || errMsg.indexOf('resource_exhausted') !== -1;
                if (isQuotaErr) {
                    Logger.log('QUOTA EXCEPTION: Entering cooldown from caught error');
                    var cooldownExpiry2 = Date.now() + QUOTA_COOLDOWN_MS;
                    CacheService.getScriptCache().put('gemini_quota_cooldown', String(cooldownExpiry2), Math.ceil(QUOTA_COOLDOWN_MS / 1000) + 10);
                    file.setDescription('retry:' + retryCount + ':' + chatId + (telegramFileId ? ':fileid:' + telegramFileId : ''));
                    if (!isWebUpload) {
                        sendTelegramMessageOnce(chatId, chatId + '_quota_wait_' + today + '_' + q,
                            '⏸ <b>AI quota limit reached</b>\n' +
                            '⏳ Pausing for ~' + Math.round(QUOTA_COOLDOWN_MS / 1000) + 's, then auto-resume');
                    }
                    break; // Stop processing — resume after cooldown
                }

                var newRetry2 = retryCount + 1;
                var retryFileIdSuffix2 = telegramFileId ? ':fileid:' + telegramFileId : '';
                if (newRetry2 < MAX_RETRIES) {
                    // Silent retry
                    file.setDescription('retry:' + newRetry2 + ':' + chatId + retryFileIdSuffix2);
                    Logger.log('File ' + fileName + ' exception, silent retry ' + newRetry2 + '/' + MAX_RETRIES);
                    filesFailed++;
                } else {
                    file.setDescription('failed:' + today + ':' + fileErr.message.substring(0, 100));
                    filesFailed++;
                    if (!isWebUpload) {
                        sendTelegramMessageOnce(chatId, chatId + '_' + editionKey + '_failed',
                            '❌ <b>Failed ' + progressLabel + ':</b> ' + fileName + '\n' +
                            '🔄 All ' + MAX_RETRIES + ' attempts exhausted\n' +
                            '🐛 ' + fileErr.message + '\n' +
                            '💾 Use /process to retry or send the file again');
                    }
                }
            } catch (e2) { /* ignore */ }
        }

        // Pause between files to avoid API rate limits
        if (q < queuedFiles.length - 1) {
            Utilities.sleep(2000);
        }
    }

    // Final summary — ONE message, only if multiple files processed
    if ((filesProcessed > 0 || filesFailed > 0) && totalFiles > 1) {
        var summaryChatId = null;
        for (var sc = 0; sc < queuedFiles.length; sc++) {
            if (queuedFiles[sc].chatId && queuedFiles[sc].chatId !== 'web') {
                summaryChatId = queuedFiles[sc].chatId;
                break;
            }
        }

        if (summaryChatId) {
            var totalArticles = getTodayArticleCount();
            var summaryLines = ['📊 <b>Batch Complete</b>', ''];
            summaryLines.push('📄 Files: ' + filesProcessed + '/' + totalFiles + ' processed');
            if (filesFailed > 0) summaryLines.push('⚠️ Failed/retrying: ' + filesFailed);
            summaryLines.push('📝 Articles: ' + processedCount);
            summaryLines.push('📊 Total today: ' + totalArticles);
            if (filesFailed > 0) {
                summaryLines.push('\n💡 Failed files will auto-retry or use /process');
            } else {
                summaryLines.push('\n🎉 All files processed successfully!');
            }
            sendTelegramMessageOnce(summaryChatId, summaryChatId + '_batchsummary_' + today + '_' + totalFiles,
                summaryLines.join('\n'));
        }
    }

    // Silent admin report (admin only, no dedup needed since it's a log)
    if (filesProcessed > 0 || filesFailed > 0) {
        var adminChatId = config.ADMIN_CHAT_ID;
        if (adminChatId) {
            try {
                var adminTotal = getTodayArticleCount();
                sendTelegramMessageOnce(adminChatId, 'admin_report_' + today + '_' + startTime,
                    '🔄 <b>Processing Report</b>\n' +
                    '📄 Files: ' + filesProcessed + '/' + totalFiles +
                    (filesFailed > 0 ? ' (' + filesFailed + ' failed)' : '') + '\n' +
                    '📝 Articles: ' + processedCount + '\n' +
                    '📊 Total today: ' + adminTotal);
            } catch (notifyErr) { /* ignore */ }
        }
    }
}

// ==========================================
//  HOURLY SWEEP — Catches any stranded queued files
//  Runs every 1 hour to pick up files that were queued while
//  a previous processQueuedFiles execution was still running.
//  Also re-queues stuck "processing:" files older than 10 minutes.
// ==========================================
function sweepQueuedFiles() {
    Logger.log('Hourly sweep: checking for stranded queued files...');
    var config = getConfig();
    var folder = DriveApp.getFolderById(config.DRIVE_FOLDER_ID);
    var today = getTodayIST();
    var yesterday = getYesterdayIST();

    var foldersToCheck = [folder];
    var dateFolders = folder.getFoldersByName(today);
    if (dateFolders.hasNext()) foldersToCheck.unshift(dateFolders.next());
    var yesterdayFolders = folder.getFoldersByName(yesterday);
    if (yesterdayFolders.hasNext()) foldersToCheck.unshift(yesterdayFolders.next());

    var queuedCount = 0;
    var stuckRequeued = 0;

    for (var f = 0; f < foldersToCheck.length; f++) {
        var files = foldersToCheck[f].getFiles();
        while (files.hasNext()) {
            var file = files.next();
            if (!file.getName().toLowerCase().endsWith('.pdf')) continue;
            var desc = file.getDescription() || '';

            // Expire queued/retry files from previous days (same logic as processQueuedFiles)
            if (desc.indexOf('queued:') === 0 || desc.indexOf('retry:') === 0) {
                var sweepFileDate = Utilities.formatDate(file.getDateCreated(), IST_TIMEZONE, 'yyyy-MM-dd');
                if (sweepFileDate < today) {
                    file.setDescription('expired:' + today + ':queued_from_' + sweepFileDate);
                    Logger.log('Sweep expired stale file: ' + file.getName() + ' (queued on ' + sweepFileDate + ')');
                    continue;
                }
                queuedCount++;
            }

            // Re-queue stuck "processing:" files older than 10 minutes
            if (desc.indexOf('processing:') === 0) {
                var lastUpdated = file.getLastUpdated();
                var stuckMs = Date.now() - lastUpdated.getTime();
                if (stuckMs > 600000) { // 10 minutes
                    // Preserve file_id through re-queue
                    var sweepPayload = desc.substring('processing:'.length);
                    var sweepFidMatch = sweepPayload.match(/:fileid:(.+)$/);
                    var sweepChatId = sweepFidMatch ? sweepPayload.substring(0, sweepPayload.indexOf(':fileid:')) : sweepPayload;
                    var sweepFidSuffix = sweepFidMatch ? ':fileid:' + sweepFidMatch[1] : '';
                    file.setDescription('queued:' + sweepChatId + sweepFidSuffix);
                    stuckRequeued++;
                    Logger.log('Sweep re-queued stuck file: ' + file.getName() + ' (stuck ' + Math.round(stuckMs / 1000) + 's)');
                }
            }
        }
    }

    Logger.log('Sweep found ' + queuedCount + ' queued file(s), re-queued ' + stuckRequeued + ' stuck file(s)');

    // If there are queued files, trigger processing
    if (queuedCount > 0 || stuckRequeued > 0) {
        Logger.log('Sweep: triggering processQueuedFiles for ' + (queuedCount + stuckRequeued) + ' file(s)');
        processQueuedFiles();
    }
}

// Helper: Re-queue all failed AND stuck-processing files so /process can retry them
function requeueFailedFiles_() {
    var config = getConfig();
    var folder = DriveApp.getFolderById(config.DRIVE_FOLDER_ID);
    var today = getTodayIST();
    var foldersToCheck = [folder];
    var dateFolders = folder.getFoldersByName(today);
    if (dateFolders.hasNext()) foldersToCheck.unshift(dateFolders.next());

    var requeued = 0;
    for (var f = 0; f < foldersToCheck.length; f++) {
        var files = foldersToCheck[f].getFiles();
        while (files.hasNext()) {
            var file = files.next();
            if (!file.getName().toLowerCase().endsWith('.pdf')) continue;
            var desc = file.getDescription() || '';
            if (desc.indexOf('failed:') === 0 || desc.indexOf('processing:') === 0) {
                file.setDescription('queued:' + (config.ADMIN_CHAT_ID || 'web'));
                requeued++;
                Logger.log('Re-queued file: ' + file.getName() + ' (was: ' + desc.substring(0, 30) + ')');
            }
        }
    }
    Logger.log('Re-queued ' + requeued + ' file(s)');
}

// Helper: Count files currently in queue (queued: or retry:)
function countQueuedFiles_(folderId) {
    try {
        var folder = DriveApp.getFolderById(folderId);
        var today = getTodayIST();
        var count = 0;
        var foldersToCheck = [folder];
        var dateFolders = folder.getFoldersByName(today);
        if (dateFolders.hasNext()) foldersToCheck.unshift(dateFolders.next());
        for (var f = 0; f < foldersToCheck.length; f++) {
            var files = foldersToCheck[f].getFiles();
            while (files.hasNext()) {
                var file = files.next();
                if (!file.getName().toLowerCase().endsWith('.pdf')) continue;
                var desc = file.getDescription() || '';
                if (desc.indexOf('queued:') === 0 || desc.indexOf('retry:') === 0) count++;
            }
        }
        return count;
    } catch (e) { return 0; }
}

// ==========================================
//  SETUP — Run "setupAll" ONCE after deploying
// ==========================================

// Removes ALL existing triggers to prevent "too many triggers" error
function cleanupAllTriggers() {
    var triggers = ScriptApp.getProjectTriggers();
    Logger.log('Cleaning up ' + triggers.length + ' existing triggers...');
    for (var i = 0; i < triggers.length; i++) {
        ScriptApp.deleteTrigger(triggers[i]);
    }
    Logger.log('All triggers removed.');
}

// Creates exactly the triggers we need (no more, no less)
function setupTriggers() {
    // 1. Queue processor — runs every 1 minute, picks up all queued PDFs
    ScriptApp.newTrigger('processQueuedFiles')
        .timeBased()
        .everyMinutes(1)
        .create();
    Logger.log('✅ Queue trigger created (every 1 minute)');

    // 2. Hourly sweep — catches any stranded/leftover queued files
    ScriptApp.newTrigger('sweepQueuedFiles')
        .timeBased()
        .everyHours(1)
        .create();
    Logger.log('✅ Hourly sweep trigger created (every 1 hour)');

    // 3. Daily summary — runs at ~10 PM IST
    ScriptApp.newTrigger('sendDailySummary')
        .timeBased()
        .everyDays(1)
        .atHour(22)
        .create();
    Logger.log('✅ Daily summary trigger created (10 PM)');
}

// ★ THE MAIN SETUP FUNCTION — Run this ONCE after deploying ★
// Does everything: webhook + triggers + verification
function setupAll() {
    Logger.log('========== SETTING UP UPSC DAILY EDGE ==========');

    // Step 1: Clean up ALL old triggers (prevents "too many triggers")
    cleanupAllTriggers();

    // Step 2: Set up Telegram webhook
    setupWebhook();

    // Step 3: Create exactly 2 recurring triggers
    setupTriggers();

    // Step 4: Verify
    var triggers = ScriptApp.getProjectTriggers();
    Logger.log('\n✅ SETUP COMPLETE');
    Logger.log('Active triggers: ' + triggers.length);
    for (var i = 0; i < triggers.length; i++) {
        Logger.log('  • ' + triggers[i].getHandlerFunction());
    }
    Logger.log('\n📱 Now send a PDF to your bot to test!');
    Logger.log('================================================');
}

// Sets up the Telegram webhook (called by setupAll)
function setupWebhook() {
    var config = getConfig();
    var props = PropertiesService.getScriptProperties();
    var webAppUrl = props.getProperty('WEBAPP_URL');

    if (!webAppUrl) {
        webAppUrl = ScriptApp.getService().getUrl();
        if (webAppUrl.endsWith('/dev')) {
            webAppUrl = webAppUrl.replace(/\/dev$/, '/exec');
        }
        Logger.log('WARNING: WEBAPP_URL not set in Script Properties!');
        Logger.log('FIX: Deploy → Manage deployments → Copy /exec URL → Add as WEBAPP_URL');
    }

    Logger.log('Setting webhook to: ' + webAppUrl);
    var url = 'https://api.telegram.org/bot' + config.TELEGRAM_TOKEN + '/setWebhook?url=' + encodeURIComponent(webAppUrl);
    var resp = UrlFetchApp.fetch(url);
    Logger.log('Webhook result: ' + resp.getContentText());

    // Flush old pending updates
    clearWebhookQueue_();
}

// Clears all pending Telegram updates
function clearWebhookQueue_() {
    var config = getConfig();
    var token = config.TELEGRAM_TOKEN;

    UrlFetchApp.fetch('https://api.telegram.org/bot' + token + '/deleteWebhook', { muteHttpExceptions: true });
    Utilities.sleep(1000);

    var flushed = 0;
    for (var attempt = 0; attempt < 10; attempt++) {
        var resp = JSON.parse(UrlFetchApp.fetch('https://api.telegram.org/bot' + token + '/getUpdates?timeout=1&offset=-1', { muteHttpExceptions: true }).getContentText());
        if (resp.ok && resp.result && resp.result.length > 0) {
            var lastId = resp.result[resp.result.length - 1].update_id;
            UrlFetchApp.fetch('https://api.telegram.org/bot' + token + '/getUpdates?offset=' + (lastId + 1) + '&timeout=1', { muteHttpExceptions: true });
            flushed += resp.result.length;
        } else {
            break;
        }
    }
    Logger.log('Flushed ' + flushed + ' pending updates');

    // Re-set webhook
    var props = PropertiesService.getScriptProperties();
    var webAppUrl = props.getProperty('WEBAPP_URL');
    if (webAppUrl) {
        UrlFetchApp.fetch('https://api.telegram.org/bot' + token + '/setWebhook?url=' + encodeURIComponent(webAppUrl));
        Logger.log('Webhook re-set to: ' + webAppUrl);
    }
}

// Sends daily article count + newspapers processed to admin
function sendDailySummary() {
    try {
        var config = getConfig();
        var adminChatId = config.ADMIN_CHAT_ID;
        if (!adminChatId) return;

        var today = getTodayIST();
        var articleCount = getTodayArticleCount();

        var folder = DriveApp.getFolderById(config.DRIVE_FOLDER_ID);
        var dateFolders = folder.getFoldersByName(today);
        var filesTotal = 0;
        var filesOk = 0;
        var filesFailed = 0;
        var newspapers = [];

        if (dateFolders.hasNext()) {
            var dateFolder = dateFolders.next();
            var files = dateFolder.getFiles();
            while (files.hasNext()) {
                var file = files.next();
                if (!file.getName().toLowerCase().endsWith('.pdf')) continue;
                filesTotal++;
                var desc = file.getDescription() || '';
                if ((desc.indexOf('done:') === 0 || desc.indexOf('processed:') === 0) && desc.indexOf('failed') === -1 && desc.indexOf('error') === -1) {
                    filesOk++;
                    var np = detectNewspaper(file.getName());
                    if (newspapers.indexOf(np) === -1) newspapers.push(np);
                } else if (desc.indexOf('failed') !== -1 || desc.indexOf('error') !== -1) {
                    filesFailed++;
                }
            }
        }

        var grade = articleCount >= 30 ? '🟢 Excellent' : (articleCount >= 15 ? '🟡 Good' : (articleCount > 0 ? '🟠 Low' : '🔴 None'));

        sendTelegramMessage(adminChatId,
            '📊 <b>Daily Summary — ' + today + '</b>\n\n' +
            grade + '\n' +
            '📝 Total articles: <b>' + articleCount + '</b>\n' +
            '📄 PDFs processed: ' + filesOk + '/' + filesTotal +
            (filesFailed > 0 ? ' (' + filesFailed + ' failed)' : '') + '\n' +
            (newspapers.length > 0 ? '📰 Newspapers: ' + newspapers.join(', ') + '\n' : '') +
            '\n💡 Send more PDFs to increase coverage.'
        );
    } catch (err) {
        Logger.log('Daily summary error: ' + err.message);
    }
}

// ==========================================
//  DIAGNOSTICS
// ==========================================

function testSetup() {
    var props = PropertiesService.getScriptProperties();
    var checks = [];
    var allGood = true;

    var required = ['TELEGRAM_BOT_TOKEN', 'GEMINI_API_KEY', 'DRIVE_FOLDER_ID', 'FIREBASE_PROJECT_ID', 'SERVICE_ACCOUNT_JSON', 'WEBAPP_URL'];
    for (var i = 0; i < required.length; i++) {
        var val = props.getProperty(required[i]);
        if (val && val.length > 0) {
            checks.push('✅ ' + required[i] + ' = set (' + val.length + ' chars)');
        } else {
            checks.push('❌ ' + required[i] + ' = MISSING');
            allGood = false;
        }
    }

    var token = props.getProperty('TELEGRAM_BOT_TOKEN');
    if (token) {
        try {
            var meResp = JSON.parse(UrlFetchApp.fetch('https://api.telegram.org/bot' + token + '/getMe', { muteHttpExceptions: true }).getContentText());
            if (meResp.ok) {
                checks.push('✅ Telegram bot: @' + meResp.result.username);
            } else {
                checks.push('❌ Telegram bot token INVALID');
                allGood = false;
            }
        } catch (e) {
            checks.push('❌ Telegram API error: ' + e.message);
            allGood = false;
        }
    }

    var folderId = props.getProperty('DRIVE_FOLDER_ID');
    if (folderId) {
        try {
            var folder = DriveApp.getFolderById(folderId);
            checks.push('✅ Drive folder: ' + folder.getName());
        } catch (e) {
            checks.push('❌ Drive folder INVALID: ' + e.message);
            allGood = false;
        }
    }

    // Check triggers
    var triggers = ScriptApp.getProjectTriggers();
    checks.push('\n⏱ Active triggers: ' + triggers.length);
    for (var t = 0; t < triggers.length; t++) {
        checks.push('  • ' + triggers[t].getHandlerFunction());
    }
    if (triggers.length > 5) {
        checks.push('⚠️ Too many triggers! Run setupAll() to fix.');
    }

    var report = checks.join('\n');
    Logger.log('\n========== SETUP TEST ==========\n' + report + '\n\n' + (allGood ? '✅ ALL CHECKS PASSED' : '❌ FIX THE ISSUES ABOVE') + '\n================================');
}

function testPipeline() {
    var config = getConfig();
    Logger.log('=== Pipeline Test ===');
    var allKeys = getGeminiKeys();
    Logger.log('1. Telegram Token: ' + (config.TELEGRAM_TOKEN ? 'SET' : 'MISSING'));
    Logger.log('2. Gemini Keys: ' + allKeys.length + ' configured');
    Logger.log('3. Drive Folder: ' + (config.DRIVE_FOLDER_ID ? 'SET' : 'MISSING'));
    Logger.log('4. Project ID: ' + (config.PROJECT_ID || 'MISSING'));
    Logger.log('5. Service Acct: ' + (config.SERVICE_ACCOUNT.client_email || 'MISSING'));

    var token = getFirebaseAccessToken(config);
    Logger.log('6. Firebase Auth: ' + (token ? 'OK' : 'FAILED'));

    if (token) {
        try {
            var url = 'https://firestore.googleapis.com/v1/projects/' + config.PROJECT_ID +
                '/databases/(default)/documents/articles?pageSize=1';
            var resp = UrlFetchApp.fetch(url, {
                headers: { 'Authorization': 'Bearer ' + token },
                muteHttpExceptions: true
            });
            Logger.log('7. Firestore: ' + (resp.getResponseCode() === 200 ? 'CONNECTED' : 'ERROR ' + resp.getResponseCode()));
        } catch (err) {
            Logger.log('7. Firestore: ERROR - ' + err.message);
        }
    }

    var triggers = ScriptApp.getProjectTriggers();
    Logger.log('8. Triggers: ' + triggers.length);
    for (var t = 0; t < triggers.length; t++) {
        Logger.log('   • ' + triggers[t].getHandlerFunction());
    }
    Logger.log('=== Test Complete ===');
}

// ==========================================
//  BOOK PROCESSING PIPELINE
//  Processes NCERT/reference book PDFs from Drive 'books' subfolder.
//  Extracts chapters, key topics, corrects content via Gemini AI.
//  Writes structured book + chapter data to Firestore 'books' collection.
//  Runs via manual trigger or processBookQueue (every 5 min).
// ==========================================

// Process all unprocessed books from the 'books' subfolder in Drive
function processBookQueue() {
    var lock = LockService.getScriptLock();
    if (!lock.tryLock(5000)) {
        Logger.log('processBookQueue: Another instance running. Skipping.');
        return;
    }
    try {
        _processBookQueueInternal();
    } finally {
        lock.releaseLock();
    }
}

function _processBookQueueInternal() {
    var config = getConfig();
    var rootFolder = DriveApp.getFolderById(config.DRIVE_FOLDER_ID);
    var startTime = Date.now();
    var MAX_EXECUTION_MS = 300000; // 5 min

    // Check quota cooldown
    var cache = CacheService.getScriptCache();
    var cooldown = cache.get('gemini_quota_cooldown');
    if (cooldown && parseInt(cooldown, 10) > Date.now()) {
        Logger.log('Book queue: Gemini quota cooldown active. Skipping.');
        return;
    }

    // Find or create 'books' subfolder
    var booksFolders = rootFolder.getFoldersByName('books');
    if (!booksFolders.hasNext()) {
        Logger.log('No "books" subfolder found in Drive folder. Create one and add PDFs.');
        return;
    }
    var booksFolder = booksFolders.next();

    // Collect unprocessed book PDFs (no description or queued: prefix)
    var pending = [];
    var files = booksFolder.getFiles();
    while (files.hasNext()) {
        var file = files.next();
        if (!file.getName().toLowerCase().endsWith('.pdf')) continue;
        var desc = file.getDescription() || '';
        if (desc === '' || desc.indexOf('book_queued') === 0 || desc.indexOf('book_retry') === 0) {
            if (desc === '') file.setDescription('book_queued');
            pending.push(file);
        }
    }

    if (pending.length === 0) {
        Logger.log('Book queue: No pending books to process.');
        return;
    }

    Logger.log('Book queue: Found ' + pending.length + ' book(s) to process');

    for (var i = 0; i < pending.length; i++) {
        if (Date.now() - startTime > MAX_EXECUTION_MS) {
            Logger.log('Book queue: Time budget exceeded. ' + (pending.length - i) + ' books deferred.');
            break;
        }

        var file = pending[i];
        var fileName = file.getName();

        try {
            file.setDescription('book_processing');
            Logger.log('Processing book (' + (i + 1) + '/' + pending.length + '): ' + fileName);

            var blob = file.getBlob();
            var pdfBytes = blob.getBytes();
            if (pdfBytes.length < 1000) {
                throw new Error('PDF too small: ' + pdfBytes.length + ' bytes');
            }

            var bookMeta = parseBookFilename(fileName);
            var result = extractBookWithGemini(blob, bookMeta, config);

            if (result && result.chapters && result.chapters.length > 0) {
                writeBookToFirestore(result, config);
                file.setDescription('book_done:' + result.chapters.length + 'chapters');
                Logger.log('SUCCESS: ' + fileName + ' → ' + result.chapters.length + ' chapters written to Firestore');
            } else {
                var errMsg = (result && result.error) || 'No chapters extracted';
                var desc = file.getDescription() || '';
                var retryCount = 0;
                if (desc.indexOf('book_retry:') === 0) {
                    retryCount = parseInt(desc.split(':')[1], 10) || 0;
                }
                if (retryCount < 2) {
                    file.setDescription('book_retry:' + (retryCount + 1));
                    Logger.log('Book retry ' + (retryCount + 1) + '/2: ' + fileName + ' — ' + errMsg);
                } else {
                    file.setDescription('book_failed:' + errMsg.substring(0, 100));
                    Logger.log('Book FAILED: ' + fileName + ' — ' + errMsg);
                }

                // Check for quota exhaustion
                if (result && result.isQuotaExhausted) {
                    var cooldownExpiry = Date.now() + 65000;
                    cache.put('gemini_quota_cooldown', String(cooldownExpiry), 75);
                    Logger.log('Book queue: Quota exhausted, entering cooldown.');
                    break;
                }
            }
        } catch (err) {
            Logger.log('Book processing error for ' + fileName + ': ' + err.message);
            file.setDescription('book_retry:1');
        }

        // Pause between books
        if (i < pending.length - 1) Utilities.sleep(3000);
    }
}

// Parse book filename to extract metadata
function parseBookFilename(fileName) {
    var name = fileName.replace(/\.pdf$/i, '');

    // Detect class number
    var classMatch = name.match(/Class[\-\s]*(\d+)/i);
    var classNum = classMatch ? parseInt(classMatch[1], 10) : null;

    // Detect subject
    var subjects = {
        'Science': 'Science & Technology',
        'Mathematics': 'Mathematics',
        'History': 'History',
        'Geography': 'Geography',
        'Political Science': 'Polity',
        'Polity': 'Polity',
        'Economics': 'Economy',
        'Economy': 'Economy',
        'Biology': 'Science & Technology',
        'Chemistry': 'Science & Technology',
        'Physics': 'Science & Technology',
        'English': 'English',
        'Environment': 'Environment',
        'Sociology': 'Social Issues',
        'Art and Culture': 'Art & Culture'
    };

    var detectedSubject = 'General';
    var subjectKeys = Object.keys(subjects);
    for (var s = 0; s < subjectKeys.length; s++) {
        if (name.toLowerCase().indexOf(subjectKeys[s].toLowerCase()) !== -1) {
            detectedSubject = subjects[subjectKeys[s]];
            break;
        }
    }

    // Detect author for non-NCERT books
    var author = 'NCERT';
    if (name.indexOf('RS Sharma') !== -1 || name.indexOf('RS-Sharma') !== -1) author = 'R.S. Sharma';
    else if (name.indexOf('Satish Chandra') !== -1 || name.indexOf('SATISH CHANDRA') !== -1) author = 'Satish Chandra';
    else if (name.indexOf('Bipan Chandra') !== -1 || name.indexOf('BIPAN CHANDRA') !== -1) author = 'Bipan Chandra';
    else if (name.indexOf('NCERT') === -1 && classNum === null) author = 'Various';

    // Build readable title
    var title = name
        .replace(/[-_]+/g, ' ')
        .replace(/\s+/g, ' ')
        .replace(/\(\d+\)/g, '')
        .replace(/\.pdf/gi, '')
        .trim();

    return {
        title: title,
        author: author,
        subject: detectedSubject,
        classNum: classNum,
        fileName: fileName,
        level: classNum ? (classNum <= 8 ? 'Foundation' : classNum <= 10 ? 'Beginner' : 'Intermediate') : 'Intermediate'
    };
}

// Extract book content using Gemini AI
function extractBookWithGemini(pdfBlob, bookMeta, config) {
    var keys = getGeminiKeys();
    if (keys.length === 0) return { chapters: null, error: 'No Gemini API keys' };

    var pdfBytes = pdfBlob.getBytes();
    var base64Pdf = Utilities.base64Encode(pdfBytes);
    var fileSizeMB = (pdfBytes.length / (1024 * 1024)).toFixed(1);

    Logger.log('Book extraction: ' + bookMeta.title + ' (' + fileSizeMB + ' MB)');

    var prompt = 'You are an expert UPSC Civil Services Examination educator. ' +
        'Analyze this book PDF ("' + bookMeta.title + '" by ' + bookMeta.author + ', Subject: ' + bookMeta.subject + ') ' +
        'and extract its COMPLETE content chapter by chapter.\n\n' +
        'For EACH chapter provide:\n' +
        '1. chapterNumber: Sequential number (1, 2, 3...)\n' +
        '2. chapterTitle: Exact chapter title from the book\n' +
        '3. content: The COMPLETE text content of the chapter, cleaned and well-formatted. ' +
        'Fix any OCR errors, grammar mistakes, and formatting issues. ' +
        'Preserve all factual information, dates, names, statistics accurately. ' +
        'Use proper paragraphs, headings, and bullet points where appropriate.\n' +
        '4. summary: 3-5 sentence summary of the chapter\'s main points\n' +
        '5. keyTopics: Array of 5-10 main topics/concepts covered (e.g. ["Fundamental Rights", "Article 14-18", "Right to Equality"])\n' +
        '6. keyTerms: Object with 3-8 important terms and their one-line definitions\n' +
        '7. upscRelevance: How this chapter is relevant for UPSC (1-2 sentences)\n' +
        '8. examTips: 2-3 exam preparation tips specific to this chapter\'s content\n' +
        '9. practiceQuestions: Array of 3 practice questions a UPSC aspirant should be able to answer after reading\n\n' +
        'QUALITY RULES:\n' +
        '- Extract ALL chapters, do not skip any\n' +
        '- Fix OCR artifacts (broken words, misread characters, garbled text)\n' +
        '- Correct grammar and vocabulary while preserving meaning\n' +
        '- For tables/data, convert to clean text format\n' +
        '- Ensure factual accuracy — cross-reference known facts\n' +
        '- Mark constitutional articles, dates, and statistics precisely\n' +
        '- Content should be comprehensive — include all important details from each chapter\n\n' +
        'Return ONLY a valid JSON object:\n' +
        '{"bookTitle":"...","author":"...","subject":"...","totalChapters":N,"description":"2-3 line book description",' +
        '"chapters":[{"chapterNumber":1,"chapterTitle":"...","content":"...","summary":"...",' +
        '"keyTopics":["..."],"keyTerms":{"term":"def"},"upscRelevance":"...","examTips":["..."],' +
        '"practiceQuestions":["..."]}]}';

    var lastError = '';
    var anyQuotaHit = false;

    for (var k = 0; k < keys.length; k++) {
        var keyLabel = 'BookKey-' + (k + 1) + '/' + keys.length;

        var models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
        for (var m = 0; m < models.length; m++) {
            var model = models[m];
            var url = 'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent?key=' + keys[k];

            try {
                var response = UrlFetchApp.fetch(url, {
                    method: 'post',
                    contentType: 'application/json',
                    payload: JSON.stringify({
                        contents: [{
                            parts: [
                                { inline_data: { mime_type: 'application/pdf', data: base64Pdf } },
                                { text: prompt }
                            ]
                        }],
                        generationConfig: {
                            temperature: 0.2,
                            maxOutputTokens: 131072
                        }
                    }),
                    muteHttpExceptions: true
                });

                var httpCode = response.getResponseCode();
                var responseText = response.getContentText();

                if (httpCode !== 200) {
                    lastError = model + ': HTTP ' + httpCode;
                    var errLower = responseText.toLowerCase();
                    if (errLower.indexOf('429') !== -1 || errLower.indexOf('quota') !== -1 ||
                        errLower.indexOf('resource_exhausted') !== -1) {
                        anyQuotaHit = true;
                    }
                    Logger.log(keyLabel + ' ' + lastError);
                    continue;
                }

                var data = JSON.parse(responseText);
                if (!data.candidates || data.candidates.length === 0) {
                    lastError = model + ': No candidates';
                    continue;
                }

                var candidate = data.candidates[0];
                if (!candidate.content || !candidate.content.parts || !candidate.content.parts[0].text) {
                    lastError = model + ': Empty content';
                    continue;
                }

                var textContent = candidate.content.parts[0].text.trim();
                if (textContent.substring(0, 3) === '```') {
                    textContent = textContent.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
                }

                var result;
                try {
                    result = JSON.parse(textContent);
                } catch (pe) {
                    var jsonMatch = textContent.match(/\{[\s\S]*"chapters"[\s\S]*\}/);
                    if (jsonMatch) {
                        result = JSON.parse(jsonMatch[0]);
                    } else {
                        lastError = model + ': JSON parse failed';
                        continue;
                    }
                }

                if (!result.chapters || result.chapters.length === 0) {
                    lastError = model + ': No chapters extracted';
                    continue;
                }

                // Merge metadata
                result.bookTitle = result.bookTitle || bookMeta.title;
                result.author = result.author || bookMeta.author;
                result.subject = bookMeta.subject; // Use our detection
                result.level = bookMeta.level;
                result.fileName = bookMeta.fileName;
                result.classNum = bookMeta.classNum;

                Logger.log('Book extracted: ' + result.chapters.length + ' chapters using ' + model);
                return result;

            } catch (fetchErr) {
                lastError = model + ': ' + fetchErr.message;
                Logger.log(keyLabel + ' ' + lastError);
            }
        }

        // Wait between keys
        if (k < keys.length - 1) Utilities.sleep(10000);
    }

    return { chapters: null, error: lastError, isQuotaExhausted: anyQuotaHit };
}

// Write extracted book data to Firestore
function writeBookToFirestore(bookData, config) {
    var accessToken = getFirebaseAccessToken(config);
    if (!accessToken) {
        Logger.log('writeBookToFirestore: Failed to get access token');
        return;
    }

    var projectId = config.PROJECT_ID;
    var baseUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents';

    // Generate stable book ID from filename
    var bookId = 'book_' + shortHash(bookData.fileName) + '_' + (bookData.subject || 'gen').substring(0, 3).toLowerCase();

    // Write book metadata document
    var bookDoc = {
        fields: {
            id: { stringValue: bookId },
            title: { stringValue: bookData.bookTitle || '' },
            author: { stringValue: bookData.author || '' },
            description: { stringValue: bookData.description || '' },
            subject: { stringValue: bookData.subject || 'General' },
            level: { stringValue: bookData.level || 'Beginner' },
            totalChapters: { integerValue: String(bookData.chapters.length) },
            classNum: { integerValue: String(bookData.classNum || 0) },
            isMustRead: { booleanValue: false },
            rating: { doubleValue: 4.5 },
            tags: { arrayValue: { values: [{ stringValue: 'NCERT' }, { stringValue: bookData.subject || '' }] } },
            coverUrl: { stringValue: '' },
            hasContent: { booleanValue: true },
            chapterIds: { arrayValue: { values: bookData.chapters.map(function(ch, idx) {
                return { stringValue: bookId + '_ch' + (idx + 1) };
            }) } },
            createdAt: { timestampValue: new Date().toISOString() }
        }
    };

    var bookUrl = baseUrl + '/books/' + bookId;
    var resp = UrlFetchApp.fetch(bookUrl, {
        method: 'patch',
        contentType: 'application/json',
        headers: { 'Authorization': 'Bearer ' + accessToken },
        payload: JSON.stringify(bookDoc),
        muteHttpExceptions: true
    });

    if (resp.getResponseCode() !== 200) {
        Logger.log('Book metadata write failed: ' + resp.getContentText().substring(0, 200));
        return;
    }

    Logger.log('Book metadata written: ' + bookId);

    // Write each chapter as a separate document in 'bookChapters' collection
    var chaptersWritten = 0;
    for (var c = 0; c < bookData.chapters.length; c++) {
        var ch = bookData.chapters[c];
        var chapterId = bookId + '_ch' + (c + 1);

        // Build keyTerms map
        var ktFields = {};
        var kt = ch.keyTerms || {};
        var ktKeys = Object.keys(kt);
        for (var ki = 0; ki < ktKeys.length; ki++) {
            ktFields[ktKeys[ki]] = { stringValue: String(kt[ktKeys[ki]] || '') };
        }

        var chapterDoc = {
            fields: {
                id: { stringValue: chapterId },
                bookId: { stringValue: bookId },
                bookTitle: { stringValue: bookData.bookTitle || '' },
                chapterNumber: { integerValue: String(ch.chapterNumber || (c + 1)) },
                chapterTitle: { stringValue: ch.chapterTitle || 'Chapter ' + (c + 1) },
                content: { stringValue: ch.content || '' },
                summary: { stringValue: ch.summary || '' },
                keyTopics: { arrayValue: { values: (ch.keyTopics || []).map(function(t) { return { stringValue: t }; }) } },
                keyTerms: { mapValue: { fields: ktFields } },
                upscRelevance: { stringValue: ch.upscRelevance || '' },
                examTips: { arrayValue: { values: (ch.examTips || []).map(function(t) { return { stringValue: t }; }) } },
                practiceQuestions: { arrayValue: { values: (ch.practiceQuestions || []).map(function(q) { return { stringValue: q }; }) } },
                subject: { stringValue: bookData.subject || '' },
                createdAt: { timestampValue: new Date().toISOString() }
            }
        };

        var chUrl = baseUrl + '/bookChapters/' + chapterId;
        try {
            var chResp = UrlFetchApp.fetch(chUrl, {
                method: 'patch',
                contentType: 'application/json',
                headers: { 'Authorization': 'Bearer ' + accessToken },
                payload: JSON.stringify(chapterDoc),
                muteHttpExceptions: true
            });
            if (chResp.getResponseCode() === 200) {
                chaptersWritten++;
            } else {
                Logger.log('Chapter write failed ' + chapterId + ': ' + chResp.getContentText().substring(0, 200));
            }
        } catch (chErr) {
            Logger.log('Chapter write error ' + chapterId + ': ' + chErr.message);
        }
    }

    Logger.log('Wrote ' + chaptersWritten + '/' + bookData.chapters.length + ' chapters for ' + bookId);
}

// Setup book processing trigger (run once)
function setupBookTrigger() {
    // Remove existing book triggers
    var triggers = ScriptApp.getProjectTriggers();
    for (var t = 0; t < triggers.length; t++) {
        if (triggers[t].getHandlerFunction() === 'processBookQueue') {
            ScriptApp.deleteTrigger(triggers[t]);
        }
    }
    // Create 5-minute trigger for book processing
    ScriptApp.newTrigger('processBookQueue')
        .timeBased()
        .everyMinutes(5)
        .create();
    Logger.log('Book processing trigger created (every 5 minutes)');
}