// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 dreamboxone
'use strict';

const instant = process.argv[2] ? new Date(process.argv[2]) : new Date();
if (!Number.isFinite(instant.getTime())) throw new Error('Invalid release date');
const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US-u-ca-persian-nu-latn', {
    timeZone: 'Asia/Tehran', year: 'numeric', month: 'numeric', day: 'numeric'
}).formatToParts(instant).map(part => [part.type, part.value]));
console.log(`${Number(parts.year) - 1400}.${Number(parts.month)}.${Number(parts.day)}`);
