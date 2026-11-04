import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join, basename} from 'node:path';
import {createHash} from 'node:crypto';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const directory = join(root, 'extensions/mangadex');
const repository = JSON.parse(readFileSync(join(directory, 'repository.json'), 'utf8'));
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const book = '00000000-0000-4000-8000-000000000001';
const group = '00000000-0000-4000-8000-000000000002';
const chapterID = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const chapter = (n, lang, attributes = {}) => ({
  id: chapterID(n), type: 'chapter',
  attributes: {chapter: String(n), volume: '1', title: 'Title', translatedLanguage: lang, pages: 2, externalUrl: null, ...attributes},
  relationships: [{type: 'scanlation_group', id: group, attributes: {name: 'Example group'}}]
});
const response = data => ({text: JSON.stringify(data), json: () => structuredClone(data)});
const ok = data => ({result: 'ok', data});

for (const manifest of repository.extensions) {
  const code = readFileSync(join(directory, 'dist', basename(new URL(manifest.script).pathname)), 'utf8');
  assert.equal(createHash('sha256').update(code).digest('hex'), manifest.sha256);
  assert.deepEqual(manifest.hosts, ['api.mangadex.org', 'uploads.mangadex.org', '*.mangadex.network']);
  const language = manifest.id.split('.').at(-1);
  const invoke = new AsyncFunction('operation', 'input', 'api', code + '\nreturn JSON.stringify(await source[operation](input, api));');
  const call = async (operation, input, handler) => JSON.parse(await invoke(operation, input, {request: async value => {
    const url = new URL(value);
    assert.equal(url.origin, 'https://api.mangadex.org');
    return response(await handler(url));
  }}));
  const title = {
    id: book, type: 'manga', attributes: {
      title: {en: 'English title', [language]: 'Local title'}, contentRating: 'safe',
      description: {[language]: 'Description'}, tags: [{attributes: {group: 'genre', name: {en: 'Adventure'}}}]
    }, relationships: [
      {type: 'author', attributes: {name: 'Author'}}, {type: 'artist', attributes: {name: 'Author'}},
      {type: 'cover_art', attributes: {fileName: 'cover.jpg'}}
    ]
  };
  const titles = await call('search', {query: 'a&contentRating[]=pornographic'}, url => {
    assert.equal(url.searchParams.get('title'), 'a&contentRating[]=pornographic');
    assert.deepEqual(url.searchParams.getAll('contentRating[]'), ['safe']);
    assert.equal(url.searchParams.get('availableTranslatedLanguage[]'), language);
    return ok([title, {...title, id: chapterID(9), attributes: {...title.attributes, contentRating: 'pornographic'}}]);
  });
  assert.equal(titles.length, 1);
  assert.equal(titles[0].title, 'Local title');
  assert.equal(titles[0].author, 'Author');
  assert.equal(titles[0].genre, 'Adventure');
  assert.match(titles[0].cover, /\.256\.jpg$/);
  const noCover = structuredClone(title); noCover.relationships = [];
  const fallback = await call('search', {query: ''}, url => {
    assert.equal(url.searchParams.get('order[followedCount]'), 'desc');
    return ok([noCover]);
  });
  assert.equal(fallback[0].cover, null);

  let feedCalls = 0;
  const chapterHandler = url => {
    if (url.pathname === '/manga/' + book) return ok(title);
    assert.equal(url.pathname, '/manga/' + book + '/feed');
    assert.equal(url.searchParams.get('translatedLanguage[]'), language);
    assert.equal(url.searchParams.get('includeExternalUrl'), '0');
    const offset = Number(url.searchParams.get('offset'));
    feedCalls++;
    const entries = offset === 0 ? [chapter(11, language), chapter(12, language, {externalUrl: 'https://example.org'})]
      : [chapter(13, language), chapter(14, 'xx'), chapter(15, language, {pages: 0}), chapter(16, language, {readableAt: '2999-01-01T00:00:00Z'})];
    return {result: 'ok', data: entries, offset, total: 6};
  };
  const chapters = await call('chapters', {mangaID: book}, chapterHandler);
  assert.equal(feedCalls, 2);
  assert.deepEqual(chapters.map(item => item.id), [chapterID(11), chapterID(13)]);
  assert(chapters.every(item => item.credit.includes('MangaDex') && item.credit.includes('Example group')));
  await assert.rejects(call('chapters', {mangaID: book}, url => url.pathname.endsWith('/feed')
    ? {result: 'ok', data: [], offset: 0, total: 10001} : ok(title)), /10,000/);
  await assert.rejects(call('chapters', {mangaID: book}, url => url.pathname.endsWith('/feed')
    ? {result: 'ok', data: [], offset: 0, total: 2} : ok(title)), /chapter list changed/);

  const chapterData = chapter(11, language);
  chapterData.relationships.push({type: 'manga', id: book, attributes: {contentRating: 'safe'}});
  const atHome = {result: 'ok', baseUrl: 'https://node.mangadex.network/temporary-token',
    chapter: {hash: 'a'.repeat(32), data: ['full.png'], dataSaver: ['small.jpg']}};
  const pagesHandler = home => url => {
    if (url.pathname.startsWith('/chapter/')) return ok(chapterData);
    assert.equal(url.searchParams.get('forcePort443'), 'true');
    return home;
  };
  const pages = await call('pages', {mangaID: book, chapterID: chapterID(11)}, pagesHandler(atHome));
  assert.deepEqual(pages, ['https://node.mangadex.network/temporary-token/data-saver/' + 'a'.repeat(32) + '/small.jpg']);
  const full = structuredClone(atHome); full.chapter.dataSaver = [];
  assert.match((await call('pages', {mangaID: book, chapterID: chapterID(11)}, pagesHandler(full)))[0], /\/data\//);
  for (const baseUrl of ['http://node.mangadex.network', 'https://mangadex.network.evil.org',
    'https://evil-mangadex.network', 'https://node.mangadex.network:444', 'https://user:secret@node.mangadex.network']) {
    await assert.rejects(call('pages', {mangaID: book, chapterID: chapterID(11)}, pagesHandler({...atHome, baseUrl})), /outside this source/);
  }
  const badFile = structuredClone(atHome); badFile.chapter.dataSaver = ['../escape.jpg'];
  await assert.rejects(call('pages', {mangaID: book, chapterID: chapterID(11)}, pagesHandler(badFile)), /invalid page/);
  await assert.rejects(call('pages', {mangaID: chapterID(99), chapterID: chapterID(11)}, pagesHandler(atHome)), /no longer available/);
  await assert.rejects(call('chapters', {mangaID: 'invalid'}, () => assert.fail('Must not request invalid IDs')), /Invalid MangaDex/);
  await assert.rejects(invoke('search', {query: ''}, {request: async () => {throw new Error('HTTP 429');}}), /rate limit/);
  await assert.rejects(invoke('search', {query: ''}, {request: async () => {throw new Error('HTTP 403');}}), /denied access/);
  const blockedCode = code.replace(/^const blockedGroupIDs = new Set\(.*\);$/m, `const blockedGroupIDs = new Set([${JSON.stringify(group)}]);`);
  const blockedCall = new AsyncFunction('input', 'api', blockedCode + '\nreturn source.chapters(input, api);');
  await assert.rejects(blockedCall({mangaID: book}, {request: async value => {
    const url = new URL(value);
    if (!url.pathname.endsWith('/feed')) return response(ok(title));
    assert.deepEqual(url.searchParams.getAll('excludedGroups[]'), [group]);
    return response({result: 'ok', data: [chapter(11, language)], offset: 0, total: 1});
  }}), /Keine direkt|No directly/);
  console.log(`PASS: MangaDex ${language}: manifest integrity, localized search, safe filter, feed pagination, credits, removal filter, valid image URLs and errors`);
}

if (process.argv.includes('--live')) {
  const manifest = repository.extensions.find(item => item.id.endsWith('.en'));
  const code = readFileSync(join(directory, 'dist', basename(new URL(manifest.script).pathname)), 'utf8');
  const invoke = new AsyncFunction('operation', 'input', 'api', code + '\nreturn JSON.stringify(await source[operation](input, api));');
  const api = {request: async url => {
    const result = await fetch(url, {headers: {'User-Agent': 'Sumi/1.0'}, signal: AbortSignal.timeout(20000)});
    if (!result.ok) throw new Error('HTTP ' + result.status);
    const text = await result.text();
    return {text, json: () => JSON.parse(text)};
  }};
  const call = async (operation, input) => JSON.parse(await invoke(operation, input, api));
  const titles = await call('search', {query: 'Give My Regards to Black Jack'});
  assert(titles.length > 0, 'Expected a live search result');
  const title = titles.find(item => item.id === '5feea066-dd12-490e-beb6-a705a9dbba7c') || titles[0];
  const chapters = await call('chapters', {mangaID: title.id});
  assert(chapters.length > 0);
  const pages = await call('pages', {mangaID: title.id, chapterID: chapters[0].id});
  const image = await fetch(pages[0], {headers: {'User-Agent': 'Sumi/1.0'}, signal: AbortSignal.timeout(20000)});
  assert(image.ok, 'Image HTTP ' + image.status);
  assert.match(image.headers.get('content-type') || '', /^image\//);
  assert((await image.arrayBuffer()).byteLength > 1000);
  console.log(`PASS LIVE: MangaDex search → ${chapters.length} chapters → ${pages.length} page URLs → image response (${new URL(pages[0]).hostname})`);
}
