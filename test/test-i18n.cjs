/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../luci-app-gozarbin/htdocs/luci-static/resources/view/gozarbin');
const source = fs.readFileSync(path.join(root, 'i18n.js'), 'utf8');
const keys = new Set();
for (const name of ['settings', 'update', 'traffic', 'appearance']) {
    const view = fs.readFileSync(path.join(root, name + '.js'), 'utf8');
    for (const match of view.matchAll(/_\('((?:[^'\\]|\\.)*)'\)/g)) keys.add(match[1]);
}
for (const language of ['fa', 'en', 'ru', 'zh']) {
    const module = new Function('baseclass', 'window', source)(
        { extend: value => value }, { localStorage: { getItem: () => language } });
    assert.equal(module.get(), language);
    assert.equal(module.dir(), language === 'fa' ? 'rtl' : 'ltr');
    for (const key of keys) {
        const value = module.tr(key);
        assert.equal(typeof value, 'string');
        assert.ok(value.length, key);
        if (language !== 'fa' && /[\u0600-\u06ff]/.test(key)) {
            assert.notEqual(value, key, 'Missing ' + language + ': ' + key);
            assert.ok(!/[\u0600-\u06ff]/.test(value), 'Persian text in ' + language + ': ' + key);
        }
    }
    console.log('PASS:', language, keys.size, 'translated messages and layout direction');
}
