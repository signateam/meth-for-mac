// Sends every request to https://trymeth.com, then serves the static site.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === 'http:' || url.hostname === 'www.trymeth.com') {
      url.protocol = 'https:';
      url.hostname = 'trymeth.com';
      return Response.redirect(url.toString(), 301);
    }
    return env.ASSETS.fetch(request);
  },
};
