// Unofficial MangaDex adapter for Sumi Source API v1.
// Built by scripts/build_mangadex_repository.py; do not edit generated dist files.
const language = "de";
const blockedGroupIDs = new Set([]);
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

function contentRatings(allowNSFW) {
  return allowNSFW === 'true' ? ['safe', 'suggestive', 'erotica', 'pornographic'] : ['safe'];
}

const source = {
  async filters(_, api) {
    const response = await getJSON(api, '/manga/tag');
    if (!Array.isArray(response.data)) throw new Error('MangaDex returned an invalid tag list.');
    return {
      supportsNSFW: true, supportsExcludedTags: true,
      groups: [
        {id: 'demographic', name: 'Demographic', multiple: true, options: ['shounen', 'shoujo', 'seinen', 'josei', 'none'].map(id => ({id, name: id}))},
        {id: 'originalLanguage', name: 'Original language', multiple: true, options: ['ja', 'ko', 'zh', 'zh-hk', 'en', 'de', 'fr', 'es', 'ru', 'vi', 'th', 'id', 'it', 'pt-br'].map(id => ({id, name: id}))},
        {id: 'contentRating', name: 'Content rating', multiple: true, options: ['safe', 'suggestive', 'erotica', 'pornographic'].map(id => ({id, name: id}))},
        {id: 'year', name: 'Publication year', options: []},
        {id: 'author', name: 'Author name', options: []},
        {id: 'artist', name: 'Artist name', options: []},
        {id: 'excludedTagsMode', name: 'Match excluded tags', options: ['AND', 'OR'].map(id => ({id, name: id}))},
        {id: 'hasAvailableChapters', name: 'Available chapters', options: [{id: 'true', name: 'With chapters'}, {id: 'false', name: 'Without chapters'}]}
      ],
      tags: response.data.map(tag => ({id: uuid(tag.id), name: localized(tag.attributes?.name)})),
      statuses: ['ongoing', 'completed', 'hiatus', 'cancelled'].map(id => ({id, name: id[0].toUpperCase() + id.slice(1)})),
      sortOrders: [
        {id: 'popular', name: 'Most popular'}, {id: 'latest', name: 'Recently updated'},
        {id: 'newest', name: 'Recently added'}, {id: 'title', name: 'Title A–Z'},
        ...['title', 'year', 'createdAt', 'updatedAt', 'latestUploadedChapter', 'followedCount', 'relevance', 'rating'].flatMap(field =>
          ['asc', 'desc'].map(direction => ({id: field + ':' + direction, name: field + ' · ' + direction})))
      ]
    };
  },

  async search({ query, allowNSFW = 'false', tags = '[]', tagMode = 'AND', status = '', sort = '', excludedTags = '[]', filters = '{}', page }, api) {
    const term = String(query || '').trim();
    const number = page === undefined ? 1 : Number(page);
    if (!Number.isSafeInteger(number) || number < 1 || number > 200) throw new Error('Invalid MangaDex catalog page.');
    const offset = (number - 1) * 50;
    const selectedTags = JSON.parse(tags);
    const excluded = JSON.parse(excludedTags);
    const extra = JSON.parse(filters);
    if (!Array.isArray(excluded) || excluded.length > 500 || !extra || typeof extra !== 'object' || Array.isArray(extra)) throw new Error('Invalid filters.');
    const known = ['demographic', 'originalLanguage', 'contentRating', 'year', 'hasAvailableChapters', 'excludedTagsMode', 'author', 'artist'];
    for (const [key, values] of Object.entries(extra)) {
      if (!known.includes(key) || !Array.isArray(values) || values.some(v => typeof v !== 'string')) throw new Error('Invalid filter group.');
    }
    if (!Array.isArray(selectedTags) || selectedTags.length > 500) throw new Error('Invalid tags.');
    if (!['AND', 'OR'].includes(tagMode)) throw new Error('Invalid tag matching mode.');
    if (status && !['ongoing', 'completed', 'hiatus', 'cancelled'].includes(status)) throw new Error('Invalid status.');
    const orders = {popular: ['followedCount', 'desc'], latest: ['latestUploadedChapter', 'desc'],
      newest: ['createdAt', 'desc'], title: ['title', 'asc']};
    for (const field of ['title', 'year', 'createdAt', 'updatedAt', 'latestUploadedChapter', 'followedCount', 'relevance', 'rating']) {
      for (const direction of ['asc', 'desc']) orders[field + ':' + direction] = [field, direction];
    }
    if (sort && !Object.hasOwn(orders, sort)) throw new Error('Invalid sort order.');
    const order = sort ? orders[sort] : [term ? 'relevance' : 'followedCount', 'desc'];
    const parameters = [
      ['limit', 50], ['offset', offset], ...contentRatings(allowNSFW).filter(rating => !extra.contentRating?.length || extra.contentRating.includes(rating)).map(rating => ['contentRating[]', rating]), ['availableTranslatedLanguage[]', language],
      ['includes[]', 'author'], ['includes[]', 'artist'], ['includes[]', 'cover_art'],
      ['order[' + order[0] + ']', order[1]]
    ];
    if (term) parameters.push(['title', term]);
    for (const tag of new Set(selectedTags)) parameters.push(['includedTags[]', uuid(tag)]);
    if (selectedTags.length) parameters.push(['includedTagsMode', tagMode]);
    if (status) parameters.push(['status[]', status]);
    for (const tag of new Set(excluded)) parameters.push(['excludedTags[]', uuid(tag)]);
    if (excluded.length) parameters.push(['excludedTagsMode', extra.excludedTagsMode?.[0] || 'OR']);
    for (const [key, parameter] of [['demographic', 'publicationDemographic[]'], ['originalLanguage', 'originalLanguage[]']]) {
      for (const value of extra[key] || []) parameters.push([parameter, value]);
    }
    for (const key of ['year', 'hasAvailableChapters']) if (extra[key]?.length) parameters.push([key, extra[key][0]]);
    if (extra.contentRating?.length && !extra.contentRating.some(rating => contentRatings(allowNSFW).includes(rating))) {
      throw new Error('Enable NSFW content to use the selected content rating.');
    }
    for (const [key, parameter] of [['author', 'authors[]'], ['artist', 'artists[]']]) {
      const name = extra[key]?.[0]?.trim();
      if (!name) continue;
      const matches = await getJSON(api, '/author', [['name', name], ['limit', 100]]);
      if (!Array.isArray(matches.data)) throw new Error('MangaDex returned invalid creator results.');
      if (!matches.data.length) return page === undefined ? [] : {titles: [], nextPage: null};
      for (const creator of matches.data) parameters.push([parameter, uuid(creator.id)]);
    }
    const response = await getJSON(api, '/manga', parameters);
    if (!Array.isArray(response.data)) throw new Error('MangaDex returned an invalid title list.');
    const allowedRatings = contentRatings(allowNSFW).filter(rating => !extra.contentRating?.length || extra.contentRating.includes(rating));
    const titles = response.data.filter(item => item.type === 'manga' && allowedRatings.includes(item.attributes?.contentRating))
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
    if (page === undefined) return titles;
    if (!Number.isInteger(response.total) || response.total < 0 || response.offset !== offset || response.data.length > 50) {
      throw new Error('MangaDex returned invalid catalog pagination.');
    }
    const hasNext = response.data.length > 0 && offset + response.data.length < Math.min(response.total, 10000);
    return {titles, nextPage: hasNext ? String(number + 1) : null};
  },

  async chapters({ mangaID, allowNSFW = 'false' }, api) {
    uuid(mangaID);
    const manga = await getJSON(api, '/manga/' + mangaID);
    if (!contentRatings(allowNSFW).includes(manga.data?.attributes?.contentRating)) {
      throw new Error('This title is hidden by the source content setting. Enable NSFW content in this source to read it.');
    }
    const results = new Map();
    let offset = 0;
    let total = 1;
    while (offset < total) {
      const parameters = [
        ['limit', 500], ['offset', offset], ['translatedLanguage[]', language],
        ...contentRatings(allowNSFW).map(rating => ['contentRating[]', rating]), ['includes[]', 'scanlation_group'], ['includes[]', 'user'],
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

  async pages({ mangaID, chapterID, allowNSFW = 'false' }, api) {
    uuid(mangaID); uuid(chapterID);
    const chapter = await getJSON(api, '/chapter/' + chapterID, [
      ['includes[]', 'manga'], ['includes[]', 'scanlation_group']
    ]);
    const manga = relationships(chapter.data || {}, 'manga').find(item => item.id === mangaID);
    if (chapter.data?.id !== chapterID || !manga || !contentRatings(allowNSFW).includes(manga.attributes?.contentRating) || !readable(chapter.data)) {
      throw new Error('This chapter is no longer available through this source. Open the title again.');
    }
    const response = await getJSON(api, '/at-home/server/' + chapterID, [['forcePort443', 'true']]);
    let base;
    try { base = new URL(response.baseUrl); } catch { throw new Error('MangaDex returned an invalid image server.'); }
    if (base.protocol !== 'https:' || base.username || base.password || base.port || base.search || base.hash ||
        !(base.hostname === 'uploads.mangadex.org' || base.hostname.endsWith('.mangadex.network'))) {
      throw new Error('MangaDex selected an image host outside this source’s permissions.');
    }
    const original = response.chapter?.data;
    const saver = !Array.isArray(original) || original.length === 0;
    const files = saver ? response.chapter?.dataSaver : original;
    const hash = response.chapter?.hash;
    if (typeof hash !== 'string' || !/^[a-f0-9]{32,64}$/i.test(hash) || !Array.isArray(files) ||
        !files.length || files.length > 500 || files.some(file => typeof file !== 'string' || !file || /[/\\]/.test(file) || file === '.' || file === '..')) {
      throw new Error('MangaDex returned an empty or invalid page list.');
    }
    return files.map(file => base.href.replace(/\/+$/, '') + (saver ? '/data-saver/' : '/data/') + hash + '/' + encodeURIComponent(file));
  }
};
