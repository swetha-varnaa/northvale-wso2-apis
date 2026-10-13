// Copies _shared/http.js into every service's src/ so each folder builds alone.
const fs = require('node:fs'); const path = require('node:path');
const root = path.join(__dirname, '..');
for (const s of ['kyb-screening', 'credit-bureau', 'identity-provisioning', 'workforce-calendar']) {
  fs.copyFileSync(path.join(root, '_shared/http.js'), path.join(root, s, 'src/http.js'));
  console.log('synced', s);
}
