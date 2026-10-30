/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require baseclass';
'require fs';
'require ui';
'require poll';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;
var storageNodes = {};

return baseclass.extend({
	paths: function() {
		var section = E('section', { 'class': 'ae-update ae-storage' }, E('h3', {}, _('محل ذخیره سازی')));
		[
			['app', _('پوشه برنامه'), '/usr/share/gozarbin'],
			['ui', _('پوشه رابط کاربری'), '/www/luci-static/resources/view/gozarbin'],
			['config', _('پوشه تنظیمات و هویت ها'), '/etc/gozarbin'],
			['aether', _('پوشه هسته اتر'), '—'],
			['singbox', _('پوشه هسته سینگ باکس'), '—']
		].forEach(function(item) {
			var node = E('bdi', { 'class': 'ae-storage-path', 'dir': 'ltr' }, item[2]);
			storageNodes[item[0]] = node;
			section.appendChild(E('div', { 'class': 'ae-app-row' }, [E('strong', {}, item[1]), node]));
		});
		return section;
	},
	geo: function() {
		var rows = {}, section = E('section', { 'class': 'ae-update ae-geo-update' }, E('h3', {}, 'GeoIP / GeoSite'));
		var wasBusy = false, completedUntil = 0;
		function date(value) {
			if (!(Number(value) > 0)) return _('هنوز دریافت نشده');
			return new Intl.DateTimeFormat(i18n.get() === 'fa' ? 'fa-IR-u-ca-persian' : 'en-US-u-ca-persian', {
				year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
				hourCycle: 'h23', timeZone: 'Asia/Tehran'
			}).format(new Date(Number(value) * 1000));
		}
		function apply(state) {
			var busy = ['starting', 'geo-downloading'].indexOf(state.state) >= 0;
			if (state.state === 'done' && wasBusy) completedUntil = Date.now() + 15000;
			wasBusy = busy;
			Object.keys(rows).forEach(function(key) {
				var row = rows[key], active = state.target === key || state.target === 'all';
				row.button.disabled = busy;
				row.updated.textContent = date(state.files && state.files[key]);
				row.status.classList.toggle('ae-message-error', state.state === 'error');
				row.status.hidden = !active || !state.state || state.state === 'idle' || (state.state === 'done' && Date.now() > completedUntil);
				row.status.textContent = busy ? _('در حال دانلود فایل…') : state.state === 'done' ? _('فایل با موفقیت دریافت شد.') : _('دریافت فایل ناموفق بود.');
			});
		}
		function failure(error, key) {
			Object.keys(rows).forEach(function(id) { rows[id].button.disabled = false; });
			var row = rows[key || 'geoip']; row.status.hidden = false; row.status.classList.add('ae-message-error'); row.status.textContent = error.message;
		}
		function refresh() {
			return fs.exec('/usr/libexec/gozarbin/geo-core.sh', ['status']).then(function(result) {
				if (result.code !== 0) throw new Error(result.stderr || _('دریافت فایل ناموفق بود.'));
				apply(JSON.parse(result.stdout || '{}'));
			}).catch(function(error) { failure(error); });
		}
		[['geoip', 'GeoIP'], ['geosite', 'GeoSite'], ['ads', _('فهرست تبلیغات و ردیاب ها')]].forEach(function(item) {
			var key = item[0], updated = E('bdi', { 'class': 'ae-geo-date', 'dir': 'ltr' }, '—');
			var status = E('div', { 'class': 'ae-inline-message', 'role': 'status', 'aria-live': 'polite', 'hidden': true });
			var button = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-apply', 'click': ui.createHandlerFn(null, function() {
				Object.keys(rows).forEach(function(id) { rows[id].button.disabled = true; });
				status.hidden = false; status.classList.remove('ae-message-error'); status.textContent = _('در حال دانلود فایل…');
				return fs.exec('/usr/libexec/gozarbin/geo-core.sh', ['update', key]).then(function(result) {
					if (result.code !== 0) throw new Error(result.stderr || _('دریافت فایل ناموفق بود.'));
					return refresh();
				}).catch(function(error) { failure(error, key); });
			}) }, _('دانلود'));
			rows[key] = { updated: updated, button: button, status: status };
			section.appendChild(E('div', { 'class': 'ae-geo-item', 'data-geo': key }, [
				E('div', { 'class': 'ae-app-row' }, [E('strong', {}, item[1]),
					E('div', { 'class': 'ae-geo-updated' }, [E('small', {}, _('آخرین به روزرسانی')), updated]),
					E('div', { 'class': 'ae-actions' }, button)]), status]));
		});
		poll.add(refresh, 5); refresh();
		return section;
	},
	create: function(provider) {
		var singbox = provider === 'singbox';
		var helper = '/usr/libexec/gozarbin/' + (singbox ? 'singbox-core.sh' : 'aether-core.sh');
		var title = singbox ? _('هسته سینگ باکس') : _('هسته اتر');
		var installLabel = singbox ? _('به‌روزرسانی') : _('به‌روز رسانی');
		var current = E('bdi', { 'class': 'ae-version-value' }, '—');
		var latest = E('bdi', { 'class': 'ae-version-value' }, '—');
		var published = E('span', {}, latest);
		var status = E('div', { 'class': 'ae-inline-message', 'role': 'status', 'aria-live': 'polite', 'hidden': true });
		var bar = E('progress', { 'max': 100, 'value': 0, 'aria-label': installLabel });
		var progress = E('div', { 'class': 'ae-update-progress', 'hidden': true }, bar);
		var transfer = E('bdi', { 'class': 'ae-num' });
		var releaseState = E('span', { 'class': 'ae-release-state' });
		var prerelease = E('span', { 'class': 'ae-prerelease', 'hidden': true }, _('پیش انتشار'));
		var labels = {
			idle: _('آمادهٔ بررسی'), starting: _('در حال آماده‌سازی…'), checking: _('در حال بررسی GitHub…'),
			available: _('نسخهٔ جدید آمادهٔ دریافت است'), current: _('آخرین نسخه نصب است'),
			downloading: _('در حال دریافت هسته…'), verifying: _('در حال بررسی فایل هسته…'),
			installing: _('در حال نصب هسته…'), done: _('به‌روزرسانی با موفقیت انجام شد.'),
			registering: _('در حال ثبت هویت WARP…'), clearing: _('در حال پاک‌کردن داده‌های سایفون…'),
			error: _('عملیات هسته ناموفق بود.')
		};
		var failures = {
			network: _('ارتباط با GitHub برقرار نشد؛ دوباره بررسی کنید.'),
			architecture: _('هسته برای معماری این روتر منتشر نشده است.'),
			checksum: _('کنترل SHA-256 ناموفق بود؛ هسته نصب نشد.'),
			archive: _('ساختار فایل هسته معتبر نیست؛ هسته نصب نشد.'),
			binary: _('هستهٔ دریافت‌شده با این روتر یا نسخهٔ مقصد سازگار نیست.'),
			space: _('فضای کافی برای دریافت و نصب هسته وجود ندارد.'),
			restart: _('راه‌اندازی هستهٔ جدید ناموفق بود؛ نسخهٔ قبلی بازگردانده شد.'),
			interrupted: _('عملیات هسته متوقف شده است؛ دوباره تلاش کنید.')
		};
		var busy = false, completedUntil = 0;
		function apply(state) {
			var wasBusy = busy;
			status.classList.toggle('ae-message-error', state.state === 'error');
			busy = ['starting', 'checking', 'downloading', 'verifying', 'installing', 'registering', 'clearing'].indexOf(state.state) >= 0;
			current.textContent = state.installed || '—'; latest.textContent = state.latest || '—';
			prerelease.hidden = !state.prerelease || !state.latest;
			if (storageNodes[provider]) storageNodes[provider].textContent = state.folder || '—';
			var upToDate = !busy && (state.state === 'current' || (state.latest && state.installed === state.latest));
			if (state.state === 'done' && wasBusy) completedUntil = Date.now() + 15000;
			status.textContent = state.state === 'error' ? failures[state.detail] || labels.error : labels[state.state] || labels.idle;
			check.disabled = busy; install.disabled = busy || state.state !== 'available';
			bar.value = Math.max(0, Math.min(100, Number(state.percent) || 0));
			progress.hidden = ['downloading', 'verifying', 'installing'].indexOf(state.state) < 0;
			status.hidden = !state.state || ['idle', 'available', 'current'].indexOf(state.state) >= 0 || (state.state === 'done' && Date.now() > completedUntil);
			published.hidden = !state.latest || upToDate || busy;
			releaseState.textContent = upToDate ? _('به روز است') : state.state === 'available' ? _('نسخهٔ جدید آماده است') : '';
			releaseState.classList.toggle('ae-release-current', !!upToDate);
			transfer.hidden = progress.hidden;
			transfer.textContent = Number(state.total) > 0 ?
				(Number(state.downloaded || 0) / 1048576).toFixed(2) + ' / ' + (Number(state.total) / 1048576).toFixed(2) + ' MB' : '';
		}
		function failure(error) { status.hidden = false; status.textContent = String(error.message || labels.error); check.disabled = false; }
		function refresh() {
			return fs.exec(helper, ['status']).then(function(result) {
				if (result.code !== 0) throw new Error(result.stderr || labels.error);
				apply(JSON.parse(result.stdout || '{}'));
			}).catch(failure);
		}
		function start(action) {
			status.hidden = false;
			check.disabled = true; install.disabled = true; status.textContent = labels.starting;
			return fs.exec(helper, [action]).then(function(result) {
				if (result.code !== 0) throw new Error(result.stderr || labels.error);
				return refresh();
			}).catch(failure);
		}
		var check = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-neutral',
			'click': ui.createHandlerFn(this, function() { return start('check'); }) }, _('بررسی'));
		var install = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-apply', 'disabled': true,
			'click': ui.createHandlerFn(this, function() { return start('install'); }) }, installLabel);
		poll.add(refresh, 2); refresh();
		return E('section', { 'class': 'ae-update ae-core-update', 'data-provider': singbox ? 'singbox' : 'aether' }, [
			E('h3', {}, title),
			E('div', { 'class': 'ae-app-row' }, [E('strong', {}, singbox ? 'sing-box' : 'Aether'),
				E('div', { 'class': 'ae-app-versions' }, [E('span', { 'class': 'ae-installed-version' }, current),
					published, releaseState, prerelease]),
				E('div', { 'class': 'ae-actions' }, [check, install])]),
			status, progress, transfer,
			E('p', { 'class': 'ae-help-text' }, singbox ? _('فقط هسته سینگ باکس گذربین به روز می شود؛ هسته برنامه های دیگر و تنظیمات حفظ می شوند.') : _('فقط هسته اتر و ابزارهای همراهش به‌روز می‌شوند؛ تنظیمات و رابط برنامه حفظ می‌شوند.'))
		]);
	}
});
