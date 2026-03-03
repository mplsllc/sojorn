module.exports = {
  apps: [{
    name: 'mp.ls',
    script: 'dist/server/entry.mjs',
    cwd: '/opt/sojorn/mpls-website',
    env: {
      HOST: '127.0.0.1',
      PORT: 4322,
    },
  }],
};
