// Run the installed converter unchanged; stub only filesystem/icon side effects.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const source = fs.readFileSync(process.argv[2], 'utf8');
const manifest = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
let settings = {};
const context = {
  module: {exports: {}}, exports: {}, console: {log() {}, warn() {}, error() {}},
  process: {platform: 'linux', arch: 'x64', resourcesPath: '/isolated'},
  __dirname: '/isolated', Buffer,
  require(name) {
    if (name === 'path') return path;
    if (name === 'crypto') return crypto;
    if (name === 'worker_threads') return {workerData: {}, parentPort: {on() {}, postMessage() {}}};
    if (name.includes('iconHandler')) return {getModPackIcon: async () => undefined, getOptionIconPath: async () => undefined};
    if (name.includes('utils')) return {readData: key => settings[key]};
    if (name === 'electron') return {dialog: {}, app: {getPath: () => '/isolated'}};
    if (name === '7zip-bin') return {path7za: '/isolated/7za'};
    return {};
  },
};
vm.createContext(context);
vm.runInContext(source + '\nmodule.exports.probe = extractFromManifest;', context, {timeout: 3000});
(async () => {
  const cases = [];
  let convertedOptions;
  for (const all of [false, true]) for (const enabled of [false, true]) {
    settings = {setAllOptionsActive: all, setModsActive: enabled};
    const out = await context.module.exports.probe(manifest, '/isolated/c4', 'c4', settings);
    assert.equal(out.enabled, enabled);
    assert.equal(out.options.length, 1);
    const option = out.options[0];
    assert.equal(option.enabled, true);
    assert.deepEqual(JSON.parse(JSON.stringify(option.include)), []);
    assert.equal(option.suboptions.length, 1);
    const selected = option.suboptions.filter(s => s.enabled);
    assert.equal(selected.length, 1, 'Exactly one mapping must be selected');
    assert.deepEqual(JSON.parse(JSON.stringify(selected[0].include)), ['Core']);
    convertedOptions = JSON.parse(JSON.stringify(out.options));
    cases.push({setAllOptionsActive: all, setModsActive: enabled, selected: 'Core'});
  }
  console.log(JSON.stringify({passed: true, cases, converted_options: convertedOptions,
    source_sha256: crypto.createHash('sha256').update(source).digest('hex')}, null, 2));
})().catch(error => {console.error(error); process.exitCode = 1;});
