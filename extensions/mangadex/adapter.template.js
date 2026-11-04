// Unofficial MangaDex adapter for Sumi Source API v1.
// Built by scripts/build_mangadex_repository.py; do not edit generated dist files.
const language = __SUMI_MANGADEX_LANGUAGE__;
const blockedGroupIDs = new Set(__SUMI_MANGADEX_BLOCKED_GROUPS__);
const mdAPI = 'https://api.mangadex.org';
const mdImages = 'https://uploads.mangadex.org';
let lastRequestAt = 0;

function uuid(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error('Invalid MangaDex identifier. Open the title again.');
  }
  return value;
}

function endpoint(path, entries = []) {
  const url = new URL(mdAPI + path);
  for (const [name, value] of entries) url.searchParams.append(name, String(value));
  return url.href;
}

async function getJSON(api, path, entries = []) {
  // Sequential feed requests stay below MangaDex's documented general API rate.
  const delay = 300 - (Date.now() - lastRequestAt);
  if (delay > 0) await new Promise(resolve => setTimeout(resolve, delay));
  lastRequestAt = Date.now();
  let response;
  try { response = await api.request(endpoint(path, entries)); }
  catch (error) {
    if (/429/.test(String(error))) throw new Error('MangaDex rate limit reached. Wait before trying again.');
    if (/401|403/.test(String(error))) throw new Error('MangaDex denied access. It may require authentication or restrict this connection.');
    throw error;
  }
  const value = response.json();
  if (!value || value.result !== 'ok') throw new Error('MangaDex could not complete this request. Try again later.');
  return value;
}

function localized(values) {
  if (!values || typeof values !== 'object') return '';
  return [values[language], values.en, ...Object.values(values)]
    .find(value => typeof value === 'string' && value.trim()) || '';
}

function relationships(entity, type) {
  return (entity.relationships || []).filter(item => item.type === type);
}

function blocked(entity) {
  return relationships(entity, 'scanlation_group').some(group => blockedGroupIDs.has(group.id));
}

function readable(entity) {
  const attributes = entity.attributes || {};
  const future = [attributes.publishAt, attributes.readableAt].some(value => value && Date.parse(value) > Date.now());
  return attributes.translatedLanguage === language && Number(attributes.pages) > 0 &&
    !attributes.externalUrl && !attributes.isUnavailable && !future && !blocked(entity);
}

function chapterTitle(attributes) {
  const parts = [];
  if (attributes.volume) parts.push('Vol. ' + attributes.volume);
  if (attributes.chapter) parts.push((language === 'de' ? 'Kap. ' : 'Ch. ') + attributes.chapter);
  if (attributes.title) parts.push(attributes.title);
  return parts.join(' · ') || (language === 'de' ? 'Einzelkapitel' : 'One-shot');
}

const source = {
  async search({ query }, api) {
    const term = String(query || '').trim();
    const parameters = [
      ['limit', 50], ['contentRating[]', 'safe'], ['availableTranslatedLanguage[]', language],
      ['includes[]', 'author'], ['includes[]', 'artist'], ['includes[]', 'cover_art'],
      [term ? 'order[relevance]' : 'order[followedCount]', 'desc']
    ];
    if (term) parameters.push(['title', term]);
    const response = await getJSON(api, '/manga', parameters);
    if (!Array.isArray(response.data)) throw new Error('MangaDex returned an invalid title list.');
    return response.data.filter(item => item.type === 'manga' && item.attributes?.contentRating === 'safe')
      .map(item => {
        uuid(item.id);
        const attributes = item.attributes;
        const cover = relationships(item, 'cover_art').find(art => art.attributes?.fileName);
        const authors = [...relationships(item, 'author'), ...relationships(item, 'artist')]
          .map(author => author.attributes?.name).filter(Boolean);
        const tags = (attributes.tags || []).filter(tag => tag.attributes?.group === 'genre')
          .map(tag => localized(tag.attributes?.name)).filter(Boolean);
        return {
          id: item.id,
          title: localized(attributes.title) || localized((attributes.altTitles || [])[0]) || 'Untitled',
          author: [...new Set(authors)].join(', ') || 'MangaDex',
          synopsis: localized(attributes.description) || (language === 'de' ? 'Keine Beschreibung verfügbar.' : 'No description available.'),
          genre: tags.join(' · ') || 'Manga',
          cover: cover ? mdImages + '/covers/' + item.id + '/' + encodeURIComponent(cover.attributes.fileName) + '.256.jpg' : null
        };
      });
  },

  async chapters({ mangaID }, api) {
    uuid(mangaID);
    const manga = await getJSON(api, '/manga/' + mangaID);
    if (manga.data?.attributes?.contentRating !== 'safe') {
      throw new Error('This source only includes titles rated Safe by MangaDex.');
    }
    const results = new Map();
    let offset = 0;
    let total = 1;
    while (offset < total) {
      const parameters = [
        ['limit', 500], ['offset', offset], ['translatedLanguage[]', language],
        ['contentRating[]', 'safe'], ['includes[]', 'scanlation_group'], ['includes[]', 'user'],
        ['order[volume]', 'asc'], ['order[chapter]', 'asc'], ['order[createdAt]', 'asc'],
        ['includeEmptyPages', '0'], ['includeExternalUrl', '0'], ['includeFuturePublishAt', '0'],
        ['includeFutureUpdates', '0'], ['includeUnavailable', '0']
      ];
      for (const groupID of blockedGroupIDs) parameters.push(['excludedGroups[]', groupID]);
      const response = await getJSON(api, '/manga/' + mangaID + '/feed', parameters);
      if (!Array.isArray(response.data) || !Number.isInteger(response.total) || response.total < 0 ||
          !Number.isInteger(response.offset) || response.offset !== offset || response.data.length > 500) {
        throw new Error('MangaDex returned an invalid chapter list.');
      }
      total = response.total;
      if (total > 10000) throw new Error('This title exceeds Sumi’s current limit of 10,000 chapter entries.');
      if (response.data.length === 0 && offset < total) throw new Error('The chapter list changed. Open the title again.');
      for (const item of response.data) {
        if (item.type !== 'chapter' || !readable(item)) continue;
        uuid(item.id);
        const groups = relationships(item, 'scanlation_group').map(group => group.attributes?.name).filter(Boolean);
        const uploader = relationships(item, 'user').map(user => user.attributes?.username).filter(Boolean);
        results.set(item.id, {
          id: item.id, title: chapterTitle(item.attributes),
          credit: 'MangaDex · ' + (groups.length ? [...new Set(groups)].join(', ') : uploader.join(', ') || 'No group credited')
        });
      }
      offset += response.data.length;
    }
    if (!results.size) throw new Error(language === 'de' ? 'Keine direkt lesbaren deutschen Kapitel verfügbar.' : 'No directly readable English chapters are available.');
    return [...results.values()];
  },

  async pages({ mangaID, chapterID }, api) {
    uuid(mangaID); uuid(chapterID);
    const chapter = await getJSON(api, '/chapter/' + chapterID, [
      ['includes[]', 'manga'], ['includes[]', 'scanlation_group']
    ]);
    const manga = relationships(chapter.data || {}, 'manga').find(item => item.id === mangaID);
    if (chapter.data?.id !== chapterID || !manga || manga.attributes?.contentRating !== 'safe' || !readable(chapter.data)) {
      throw new Error('This chapter is no longer available through this source. Open the title again.');
    }
    const response = await getJSON(api, '/at-home/server/' + chapterID, [['forcePort443', 'true']]);
    let base;
    try { base = new URL(response.baseUrl); } catch { throw new Error('MangaDex returned an invalid image server.'); }
    if (base.protocol !== 'https:' || base.username || base.password || base.port || base.search || base.hash ||
        !(base.hostname === 'uploads.mangadex.org' || base.hostname.endsWith('.mangadex.network'))) {
      throw new Error('MangaDex selected an image host outside this source’s permissions.');
    }
    const dataSaver = response.chapter?.dataSaver;
    const saver = Array.isArray(dataSaver) && dataSaver.length > 0;
    const files = saver ? dataSaver : response.chapter?.data;
    const hash = response.chapter?.hash;
    if (typeof hash !== 'string' || !/^[a-f0-9]{32,64}$/i.test(hash) || !Array.isArray(files) ||
        !files.length || files.length > 500 || files.some(file => typeof file !== 'string' || !file || /[/\\]/.test(file) || file === '.' || file === '..')) {
      throw new Error('MangaDex returned an empty or invalid page list.');
    }
    return files.map(file => base.href.replace(/\/+$/, '') + (saver ? '/data-saver/' : '/data/') + hash + '/' + encodeURIComponent(file));
  }
};
