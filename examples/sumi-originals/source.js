// Sumi Source API v1. build_source_repository.py inserts your static HTTPS URL.
const baseURL = __SUMI_BASE_URL__;
const source = {
  async search({ query }, api) {
    const response = await api.request(baseURL + '/catalog.json');
    const catalog = response.json();
    const term = query.trim().toLocaleLowerCase();
    return catalog.filter(item => item.title.toLocaleLowerCase().includes(term))
      .map(({ chapters, ...title }) => title);
  },
  async chapters({ mangaID }, api) {
    const response = await api.request(baseURL + '/catalog.json');
    const title = response.json().find(item => item.id === mangaID);
    if (!title) throw new Error('Title no longer available');
    return title.chapters.map(({ pages, ...chapter }) => chapter);
  },
  async pages({ mangaID, chapterID }, api) {
    const response = await api.request(baseURL + '/catalog.json');
    const chapter = response.json().find(item => item.id === mangaID)
      ?.chapters.find(item => item.id === chapterID);
    if (!chapter) throw new Error('Chapter no longer available');
    return chapter.pages;
  }
};
