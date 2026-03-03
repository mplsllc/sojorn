module.exports = {
  apps: [{
    name: 'mp.ls',
    script: '/usr/local/bin/infisical-run',
    args: '75c82bb4-72d0-419f-aa11-7fc3b06c6d5b prod -- node dist/server/entry.mjs',
    cwd: '/opt/sojorn/mpls-website',
    interpreter: 'none',
    env: {
      HOST: '127.0.0.1',
      PORT: 4322,
    },
  }],
};
