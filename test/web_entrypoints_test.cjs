const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

  test('web and Flutter use one HTML entrypoint', () => {
    const read = relative => fs.readFileSync(path.join(__dirname, '..', relative), 'utf8').replace(/\r\n/g, '\n');
    assert.ok(fs.existsSync(path.join(__dirname, '..', 'index.html')));
    assert.ok(!fs.existsSync(path.join(__dirname, '..', 'assets/html/index.html')));
    assert.match(read('lib/main.dart'), /loadFlutterAsset\('index\.html'\)/);
    assert.match(read('pubspec.yaml'), /    - index\.html/);
  });
