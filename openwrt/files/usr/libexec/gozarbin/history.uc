// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 dreamboxone
import { readfile, writefile, rename } from 'fs';

let ram = getenv('GOZARBIN_HISTORY_RAM') || '/var/run/gozarbin-traffic.json';
let disk = getenv('GOZARBIN_HISTORY_DISK') || '/etc/gozarbin/state/traffic-history.json';
let now = +(getenv('GOZARBIN_HISTORY_TIME') || time());
let boot = trim(readfile('/proc/sys/kernel/random/boot_id') || '');
let data;
try { data = json(readfile(ram) || readfile(disk) || '{}'); } catch (e) { data = {}; }
if (type(data) != 'object' || type(data.hours) != 'array') data = { hours: [], saved: 0, up: 0, down: 0 };
let hours = [];
let hour = int((now + 12600) / 3600) * 3600 - 12600;
for (let row in data.hours)
	if (type(row) == 'array' && length(row) == 3 && row[0] >= hour - 31 * 86400 && row[0] <= hour)
		push(hours, row);
data.hours = hours;
if (ARGV[0] == 'report') {
	printf('%J\n', { since: data.since || now, hours: hours, time: now });
	exit(0);
}
if (ARGV[0] == 'sample') {
	let sample = json(ARGV[1] || '{}');
	if (sample.accounting == false || sample.counters == false) exit(0);
	let up = max(0, +sample.upload || 0), down = max(0, +sample.download || 0);
	let same = data.boot == boot;
	let du = same && up >= data.up ? up - data.up : up;
	let dd = same && down >= data.down ? down - data.down : down;
	let last = hours[length(hours) - 1];
	if (!last || last[0] != hour) { last = [hour, 0, 0]; push(hours, last); }
	last[1] += du; last[2] += dd;
	data.up = up; data.down = down;
	data.since = data.since || now;
} else if (ARGV[0] == 'reset') {
	data.up = 0; data.down = 0;
} else exit(1);
data.boot = boot;
let flush = ARGV[0] == 'reset' || ARGV[2] == '--flush' || now - (+data.saved || 0) >= 900;
if (flush) data.saved = now;
if (writefile(ram + '.new', sprintf('%J', data)) == null || !rename(ram + '.new', ram)) exit(1);
if (flush) {
	if (writefile(disk + '.new', sprintf('%J', data)) == null || !rename(disk + '.new', disk)) exit(1);
}
