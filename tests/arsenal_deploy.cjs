// Only the new fixture directory is writable; the original Arsenal backend runs unchanged.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {Worker} = require('node:worker_threads');
const run = fs.realpathSync(process.argv[2]);
const config = JSON.parse(fs.readFileSync(path.join(run, 'config.json')));
const backend = path.join(run, 'backend/obfuscated_src/main');
const GameState = require(path.join(backend, 'modules/gameStateManager'));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const tree = dir => Object.fromEntries(fs.readdirSync(dir).sort().map(name => {
  const file = path.join(dir, name);
  assert.ok(fs.statSync(file).isFile(), 'Unexpected nested game file');
  return [name, sha(fs.readFileSync(file))];
}));
const save = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
async function deploy(spec, tag) {
  await GameState.restorePristineState(spec.gameDir);
  const worker = new Worker(path.join(backend, 'workers/deployWorker.js'), {workerData: spec});
  let done;
  await new Promise((resolve, reject) => {
    worker.on('message', message => {
      fs.appendFileSync(path.join(run, 'worker.jsonl'), JSON.stringify({tag, message}) + '\n');
      if (message.status === 'done') done = message;
    });
    worker.on('error', reject);
    worker.on('exit', code => code === 0 && done ? resolve() : reject(Error('Worker failed: ' + code)));
  });
  assert.equal(done.metadata.failedCount, 0);
  spec.modsList = done.updatedModsList;
  return tree(spec.gameDir);
}
async function one(priority) {
  const dir = path.join(run, priority ? 'first-priority' : 'last-priority');
  for (const name of ['game/data', 'manager', 'temp', 'library/loader/data'])
    fs.mkdirSync(path.join(dir, name), {recursive: true});
  const gameDir = path.join(dir, 'game/data');
  fs.writeFileSync(path.join(gameDir, 'base.archive'), 'Fixture official base; must remain unchanged.\n');
  const loaderDir = path.join(dir, 'library/loader/data');
  // A byte fixture is sufficient: Arsenal copies archives without executing them.
  for (const suffix of ['', '.stream', '.gpu_resources'])
    fs.writeFileSync(path.join(loaderDir, '9ba626afa44a3aa3.patch_0' + suffix), suffix ? '' : 'Loader fixture.\n');
  const own = {uuid: config.manifest.Guid, label: config.manifest.Name, path: config.zip,
    enabled: false, deployed: false, changed: false, patchFileNames: [],
    // Use the real converter's normalization of omitted Include and selection defaults.
    options: JSON.parse(JSON.stringify(config.converted_options))};
  const loader = {uuid: 'fixture-loader', label: 'Loader fixture', path: path.join(dir, 'library/loader'),
    enabled: true, deployed: false, changed: false, patchFileNames: [],
    options: [{name: 'Loader', include: ['data'], enabled: true, suboptions: []}]};
  const spec = {gameDir, dataPath: path.join(dir, 'manager'), tempDir: path.join(dir, 'temp'),
    modsList: priority ? [own, loader] : [loader, own], modsLibrary: [], setTopPriority: priority};
  const baseline = await deploy(spec, 'baseline');
  const cases = [];
  for (const choice of ['core', 'core']) {
    const mod = spec.modsList.find(m => m.uuid === own.uuid);
    mod.enabled = true; mod.changed = true;
    mod.options[0].suboptions.forEach((s, i) => {s.enabled = i === 0;});
    const actual = await deploy(spec, choice);
    const expected = {...baseline};
    for (const [file, hash] of Object.entries(config.payloads[choice]))
      expected[file.replace(/\.patch_(\d+)/, (_, index) => '.patch_' + (Number(index) + 1))] = hash;
    assert.deepEqual(actual, expected, 'Only selected mapping plus loader may be deployed');
    const repeated = await deploy(spec, choice + '-repeat');
    assert.deepEqual(repeated, actual, 'Repeat deployment must be stable');
    cases.push({choice, exact_files: actual, redeployment: 'PASS'});
  }
  spec.modsList.find(m => m.uuid === own.uuid).options[0].enabled = false;
  assert.deepEqual(await deploy(spec, 'parent-option-off'), baseline);
  spec.modsList.find(m => m.uuid === own.uuid).enabled = false;
  assert.deepEqual(await deploy(spec, 'disabled'), baseline);
  return {setTopPriority: priority, cases, option_disabled: 'PASS', removal: 'PASS'};
}
(async () => {
  const report = {result: 'PASS', cases: [await one(false), await one(true)],
    scope: 'Original deploy worker and converter; fixture archives, no real game or Electron GUI.'};
  save(path.join(run, 'results.json'), report);
})().catch(error => {console.error(error); process.exitCode = 1;});
