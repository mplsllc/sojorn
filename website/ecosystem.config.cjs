module.exports = {
  apps: [{
    name: 'sojorn-site',
    script: './dist/server/entry.mjs',
    cwd: '/opt/sojorn/website',
    env: {
      HOST: '127.0.0.1',
      PORT: 4321,
    },
  }],
};
