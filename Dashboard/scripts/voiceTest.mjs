import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

async function load(name) {
  const source = await readFile(new URL(`../src/shared/voice/${name}.ts`, import.meta.url), "utf8");
  const javascript = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
}

const { VoiceActivityDetector } = await load("voiceActivity");
const speech = await load("speechText");
const audio = await load("audioUtils");

function run(frames) {
  const vad = new VoiceActivityDetector();
  const events = [];
  for (const [rms, ms, playback] of frames) {
    events.push(...vad.process(rms, ms, Boolean(playback)).map((event) => event.type));
  }
  return events;
}
const repeat = (count, rms, ms = 20, playback = false) => Array.from({ length: count }, () => [rms, ms, playback]);

test("silence, a single click and room hum never open an utterance", () => {
  assert.deepEqual(run(repeat(100, 0.003)), []);
  assert.deepEqual(run([...repeat(50, 0.003), ...repeat(2, 0.2), ...repeat(100, 0.003)]), []);
  assert.deepEqual(run(repeat(200, 0.01)), []);
});

test("a spoken phrase ends after the silence hangover", () => {
  assert.deepEqual(run([...repeat(50, 0.003), ...repeat(60, 0.08), ...repeat(60, 0.003)]), ["speech_start", "speech_end"]);
});

test("a short cough is discarded and a mid-sentence pause does not split the utterance", () => {
  assert.deepEqual(run([...repeat(50, 0.003), ...repeat(8, 0.1), ...repeat(80, 0.003)]), ["speech_start", "speech_discarded"]);
  assert.deepEqual(
    run([...repeat(50, 0.003), ...repeat(40, 0.08), ...repeat(20, 0.003), ...repeat(40, 0.08), ...repeat(60, 0.003)]),
    ["speech_start", "speech_end"]
  );
});

test("assistant echo during playback is ignored but a loud user triggers one barge-in", () => {
  assert.deepEqual(run([...repeat(50, 0.003), ...repeat(100, 0.03, 20, true)]), []);
  assert.deepEqual(
    run([...repeat(50, 0.003), ...repeat(40, 0.2, 20, true), ...repeat(60, 0.003)]),
    ["speech_start", "barge_in", "speech_end"]
  );
});

test("a very long monologue is cut into capped utterances", () => {
  const events = run([...repeat(50, 0.003), ...repeat(2000, 0.08)]);
  assert.deepEqual(events.slice(0, 2), ["speech_start", "speech_end"]);
});

test("WAV container has a correct header for 16 kHz mono PCM", () => {
  const wav = audio.pcm16ToWav(new Int16Array([0, 1000, -1000, 32767]), 16000);
  const view = new DataView(wav.buffer);
  assert.equal(String.fromCharCode(...wav.slice(0, 4)), "RIFF");
  assert.equal(String.fromCharCode(...wav.slice(8, 12)), "WAVE");
  assert.equal(view.getUint32(24, true), 16000);
  assert.equal(view.getUint16(22, true), 1);
  assert.equal(view.getUint32(40, true), 8);
  assert.equal(wav.length, 44 + 8);
  assert.equal(view.getInt16(48, true), -1000);
});

test("resampling halves the sample count when downsampling 32 kHz to 16 kHz", () => {
  assert.equal(audio.resampleTo(new Float32Array(3200), 32000, 16000).length, 1600);
  assert.equal(audio.resampleTo(new Float32Array(100), 16000, 16000).length, 100);
});

test("Markdown is stripped for speech without losing the words", () => {
  const spoken = speech.markdownToSpeechText("# Title\n\nThis is **bold** and [a link](http://x.y).\n\n```js\nconst a = 1\n```\n\n- one\n- `two`");
  assert.equal(spoken, "Title\n\nThis is bold and a link.\none\ntwo");
});

test("streamed text is spoken sentence by sentence and reassembles exactly", () => {
  const full = "Первое предложение довольно длинное, чтобы пройти порог. Второе тоже длинное и содержит слова! Версия 3.5 вышла. Хвост без точки";
  let index = 0;
  const spoken = [];
  for (let end = 1; end <= full.length; end += 7) {
    const result = speech.extractSpeakableSentences(full.slice(0, end), index, false);
    spoken.push(...result.sentences);
    index = result.nextIndex;
  }
  spoken.push(...speech.extractSpeakableSentences(full, index, true).sentences);
  assert.equal(spoken.join(""), full);
  assert.ok(spoken.length >= 3);
});

test("text inside an unterminated code fence is held back until it closes", () => {
  const text = "Вот пример кода для вас сейчас. ```js\nconst a = 1. \nconst b = 2. ";
  assert.deepEqual(speech.extractSpeakableSentences(text, 0, false).sentences, []);
});

test("long replies are chunked within the request size limit", () => {
  const long = Array.from({ length: 200 }, (_, i) => `Sentence number ${i} is reasonably long and has words.`).join(" ");
  const chunks = speech.splitSpeechChunks(long, 500);
  assert.ok(chunks.length > 10);
  assert.ok(chunks.every((chunk) => chunk.length <= 500));
});
