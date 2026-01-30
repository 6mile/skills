#!/usr/bin/env node
/**
 * Bitcoin Daily Podcast Generator
 * Generates a ~5 min AI podcast with two hosts discussing the daily digest.
 * 
 * Usage:
 *   node podcast.js [YYYY-MM-DD]           # Generate from archived digest
 *   node podcast.js --summary <file>       # Generate from summary file
 *   node podcast.js --text "..."           # Generate from inline text
 *
 * Requires: OPENAI_API_KEY, ffmpeg
 */

const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ARCHIVE_DIR = path.join(process.env.HOME, 'workspace', 'bitcoin-dev-archive');
const OUTPUT_DIR = path.join(process.env.HOME, 'workspace', 'bitcoin-dev-archive');
const OPENAI_KEY = process.env.OPENAI_API_KEY;

// Host voices
const HOSTS = {
  alex: { voice: 'onyx', name: 'Alex', gender: 'male' },     // deep, authoritative
  maya: { voice: 'nova', name: 'Maya', gender: 'female' },    // warm, engaging
};

// ── OpenAI helpers ──

function openaiRequest(endpoint, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const options = {
      hostname: 'api.openai.com',
      path: `/v1/${endpoint}`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_KEY}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      },
    };
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const buf = Buffer.concat(chunks);
        if (res.headers['content-type']?.includes('audio')) {
          resolve(buf);
        } else {
          try { resolve(JSON.parse(buf.toString())); }
          catch { resolve(buf); }
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function generateScript(digestText) {
  console.log('📝 Generating podcast script...');
  const res = await openaiRequest('chat/completions', {
    model: 'gpt-4o',
    temperature: 0.85,
    max_tokens: 8000,
    messages: [
      {
        role: 'system',
        content: `You write podcast scripts for "Bitcoin Daily" — an entertaining, in-depth ~20 minute podcast about bitcoin development.

Two hosts who've been best friends since college:
- Alex (male): The grizzled bitcoiner. Deep technical knowledge but explains things with ridiculous analogies. Deadpan delivery. Will drop a savage one-liner and keep going like nothing happened. Thinks every soft fork proposal is "the one." Has strong opinions about mempool policy the way some people have opinions about pizza toppings. When he's deep in a topic, he GOES DEEP — 4-6 sentences explaining the mechanics, layering in humor as he builds.
- Maya (female): Wickedly smart, faster wit than Alex. She gets the tech but loves poking holes in hype. Teases Alex constantly — about his "bitcoin maximalist brain rot," his terrible analogies, his obsession with UTXOs. Flirty in a best-friends-who-roast-each-other way. Will say "that's actually kind of hot" about a clever protocol design and mean it. When she's breaking down implications or connecting dots, she holds the floor and builds a compelling argument.

Their dynamic: They finish each other's sentences, have inside jokes. Maya calls Alex out when he's being too nerdy. Alex pretends to be annoyed but clearly loves it. There's a spark between them that neither acknowledges directly — it comes out as banter. Think Han Solo and Princess Leia discussing BIPs.

CRITICAL STYLE RULES:
- This is a BITCOIN podcast. Never say "crypto" or "cryptocurrency." We are bitcoin maximalists. No shitcoins, no altcoins, no "blockchain technology." Bitcoin. Period.
- VARY THE TURN LENGTH. This is NOT a ping-pong conversation. When one host is deep in a topic, let them talk for 4-8 sentences before the other jumps in. Sometimes Alex monologues for a full paragraph explaining something technical. Sometimes Maya holds the floor connecting dots. Then they rapid-fire banter for a few lines. Mix it up — long turns, short reactions, medium exchanges. Real conversations are NOT uniform.
- Spend about 2 MINUTES per major topic. That means ~300 words per topic. Go deep. Explain the "so what" and "why should I care." Don't just skim the surface.
- After covering a topic in depth, have a brief transition — a joke, a callback, or Maya steering to the next thing.

Format rules:
- Format each line as: ALEX: text  or  MAYA: text
- Start mid-energy — they've already been chatting, the listener drops in
- Cover ALL the main topics from the digest — each one gets real depth, not a drive-by mention
- Banter naturally between topics. Tease, joke, riff. But the SUBSTANCE is the star.
- End with a sign-off that includes a callback to something from the episode
- Target ~3000-3500 words total (about 20 minutes spoken)
- NO stage directions, NO parentheticals, NO sound effects, NO [laughs] — humor comes through WORDS
- NO "crypto." Say "bitcoin" or nothing. These hosts would never say crypto.`
      },
      {
        role: 'user',
        content: `Write a podcast script based on this digest:\n\n${digestText}`
      }
    ]
  });

  if (res.error) throw new Error(`Script generation failed: ${res.error.message}`);
  return res.choices[0].message.content;
}

function parseScript(script) {
  const lines = [];
  const regex = /^(ALEX|MAYA):\s*(.+)/gm;
  let match;
  while ((match = regex.exec(script)) !== null) {
    const speaker = match[1].toLowerCase();
    const text = match[2].trim();
    if (text) {
      lines.push({ speaker, text, host: HOSTS[speaker] });
    }
  }
  return lines;
}

async function generateAudio(text, voice) {
  const res = await openaiRequest('audio/speech', {
    model: 'tts-1-hd',
    voice: voice,
    input: text,
    response_format: 'mp3',
    speed: 1.05, // slightly faster for podcast feel
  });
  if (res.error) throw new Error(`TTS failed: ${res.error.message}`);
  return res; // Buffer
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

async function generatePodcast(digestText, dateStr) {
  if (!OPENAI_KEY) {
    console.error('❌ OPENAI_API_KEY not set');
    process.exit(1);
  }

  // Check ffmpeg
  try { execSync('which ffmpeg', { stdio: 'ignore' }); }
  catch { console.error('❌ ffmpeg not found'); process.exit(1); }

  const outDir = path.join(OUTPUT_DIR, dateStr || 'latest');
  const clipsDir = path.join(outDir, 'podcast-clips');
  ensureDir(clipsDir);

  // Step 1: Generate script
  const script = await generateScript(digestText);
  const scriptPath = path.join(outDir, 'podcast-script.md');
  fs.writeFileSync(scriptPath, script);
  console.log(`📝 Script saved: ${scriptPath}`);

  // Step 2: Parse into lines
  const lines = parseScript(script);
  if (lines.length === 0) {
    console.error('❌ No dialogue lines found in script');
    console.log('Raw script:\n', script);
    process.exit(1);
  }
  console.log(`🎙️  ${lines.length} dialogue lines (${lines.filter(l => l.speaker === 'alex').length} Alex, ${lines.filter(l => l.speaker === 'maya').length} Maya)`);

  // Step 3: Generate audio for each line
  const clipFiles = [];
  // Generate a short silence clip for pauses between speakers
  const silencePath = path.join(clipsDir, 'silence.mp3');
  execSync(`ffmpeg -y -f lavfi -i anullsrc=r=24000:cl=mono -t 0.4 -q:a 9 "${silencePath}" 2>/dev/null`);

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const clipPath = path.join(clipsDir, `${String(i).padStart(3, '0')}_${line.speaker}.mp3`);

    process.stdout.write(`  🔊 Generating ${i + 1}/${lines.length} (${line.host.name})...`);
    const audioBuf = await generateAudio(line.text, line.host.voice);
    fs.writeFileSync(clipPath, audioBuf);
    console.log(` ✓ (${(audioBuf.length / 1024).toFixed(0)}KB)`);

    clipFiles.push(clipPath);

    // Add pause between different speakers
    if (i < lines.length - 1 && lines[i + 1].speaker !== line.speaker) {
      clipFiles.push(silencePath);
    }

    // Rate limit: small delay between API calls
    await new Promise(r => setTimeout(r, 200));
  }

  // Step 4: Concatenate with ffmpeg (intro + dialogue + outro)
  const introPath = path.join(__dirname, 'intro.mp3');
  const hasIntro = fs.existsSync(introPath);

  const allFiles = [];
  if (hasIntro) {
    // Normalize intro to match clip format
    const introNorm = path.join(clipsDir, 'intro_norm.mp3');
    execSync(`ffmpeg -y -i "${introPath}" -ar 44100 -ac 1 -ab 128k "${introNorm}" 2>/dev/null`);
    allFiles.push(introNorm);
  }
  allFiles.push(...clipFiles);
  // Re-use intro as outro (just the chime part — first 1.5s)
  if (hasIntro) {
    const outroPath = path.join(clipsDir, 'outro.mp3');
    execSync(`ffmpeg -y -i "${introPath}" -t 1.5 -af "afade=t=in:d=0.1,afade=t=out:st=0.8:d=0.7" -ar 44100 -ac 1 -ab 128k "${outroPath}" 2>/dev/null`);
    // Add a pause before outro
    allFiles.push(silencePath);
    allFiles.push(outroPath);
  }

  const listPath = path.join(clipsDir, 'concat.txt');
  const listContent = allFiles.map(f => `file '${f}'`).join('\n');
  fs.writeFileSync(listPath, listContent);

  const outputPath = path.join(outDir, `bitcoin-daily-${dateStr || 'latest'}.mp3`);
  console.log('🎬 Stitching podcast...');

  execSync(
    `ffmpeg -y -f concat -safe 0 -i "${listPath}" -acodec libmp3lame -ab 128k -ar 44100 "${outputPath}" 2>/dev/null`
  );

  // Get duration
  const durationRaw = execSync(
    `ffprobe -v error -show_entries format=duration -of csv=p=0 "${outputPath}" 2>/dev/null`
  ).toString().trim();
  const duration = parseFloat(durationRaw);
  const mins = Math.floor(duration / 60);
  const secs = Math.floor(duration % 60);

  // Cleanup clips
  // (keep them for now so we can re-edit)

  console.log('');
  console.log(`✅ Podcast generated!`);
  console.log(`📁 ${outputPath}`);
  console.log(`⏱️  ${mins}:${String(secs).padStart(2, '0')} duration`);
  console.log(`🎙️  ${lines.length} dialogue turns`);

  return { outputPath, duration, scriptPath, lines: lines.length };
}

// ── Main ──

async function main() {
  const args = process.argv.slice(2);
  let digestText = '';
  let dateStr = '';

  if (args[0] === '--text') {
    digestText = args.slice(1).join(' ');
    dateStr = new Date().toISOString().split('T')[0];
  } else if (args[0] === '--summary') {
    const filePath = args[1];
    if (!filePath || !fs.existsSync(filePath)) {
      console.error('❌ File not found:', filePath);
      process.exit(1);
    }
    digestText = fs.readFileSync(filePath, 'utf8');
    dateStr = path.basename(path.dirname(filePath)) || new Date().toISOString().split('T')[0];
  } else {
    // Date-based: read from archive
    dateStr = args[0] || (() => {
      const d = new Date();
      d.setDate(d.getDate() - 1);
      return d.toISOString().split('T')[0];
    })();

    const summaryPath = path.join(ARCHIVE_DIR, dateStr, 'summary.md');
    if (fs.existsSync(summaryPath)) {
      digestText = fs.readFileSync(summaryPath, 'utf8');
    } else {
      console.error(`❌ No digest found for ${dateStr}`);
      console.error(`   Run: node digest.js digest ${dateStr}`);
      process.exit(1);
    }
  }

  console.log(`🎙️  Bitcoin Daily Podcast — ${dateStr}`);
  console.log('='.repeat(40));

  await generatePodcast(digestText, dateStr);
}

main().catch(e => {
  console.error(`❌ ${e.message}`);
  process.exit(1);
});
