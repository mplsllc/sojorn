/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'img.sojorn.net' },
      { protocol: 'https', hostname: 'quips.sojorn.net' },
      { protocol: 'https', hostname: 'api.sojorn.net' },
    ],
  },
};

module.exports = nextConfig;
