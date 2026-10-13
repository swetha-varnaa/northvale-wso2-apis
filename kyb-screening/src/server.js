'use strict';
const { createApp } = require('./app');
const { log } = require('./http');
const port = Number(process.env.PORT) || 8080;
const server = createApp().listen(port, () => log('info', 'listening', { service: 'kyb-screening', port }));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
