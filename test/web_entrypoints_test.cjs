const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

for (const file of ['index.html', 'sw.js']) {
  test(`web and app entrypoints stay synchronized: ${file}`, () => {
    const read = relative => fs.readFileSync(path.join(__dirname, '..', relative), 'utf8').replace(/\r\n/g, '\n');
    assert.equal(read(file), read(`assets/html/${file}`));
  });
}
