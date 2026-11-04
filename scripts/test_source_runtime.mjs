import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {basename} from 'node:path';

// Execute the production wrapper, translating Swift's escaped newlines only.
const raw = readFileSync(new URL('../Sources/Sumi/SourceRuntime.swift', import.meta.url), 'utf8');
const body = raw.match(/let body = """([\s\S]*?)"""/)[1].replaceAll('\\\\n', '\\n');
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
const invoke = new AsyncFunction('code', 'operation', 'input', body);
const source = 'const source = { search(){return []}, chapters(){return []}, pages(){return []} };';
const repository = JSON.parse(readFileSync(new URL('../extensions/mangadex/repository.json', import.meta.url)));
for (const manifest of repository.extensions) {
    const adapter = readFileSync(new URL('../extensions/mangadex/dist/' + basename(manifest.script), import.meta.url), 'utf8');
    assert.equal(await invoke(adapter, '__validate', {}), 'true');
}
assert.equal(await invoke(source, '__validate', {}), 'true');
assert.equal(await invoke(source, 'search', {}), '[]');
assert.equal(await invoke("return 'true';", '__validate', {}), 'false');
await assert.rejects(invoke("return JSON.stringify([{synopsis:'A'.repeat(5000000)}]);", 'search', {}));
await assert.rejects(invoke(source.replace('return []', "return 'A'.repeat(4000001)"), 'search', {}), /Invalid extension result/);
await assert.rejects(invoke(source + "source.filters = () => ({ignored:'A'.repeat(4000001)});", '__filters', {}), /Invalid extension result/);
assert.equal(await invoke(source, '__filters', {}), '{"tags":[],"statuses":[],"sortOrders":[]}');
console.log('PASS: actual runtime wrapper, early return isolation, required methods, search/filter size limits and legacy extensions');
