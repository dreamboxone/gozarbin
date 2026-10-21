/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require view.gozarbin.appearance as appearance';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;

function version(value) {
	return String(value || '—').replace(/^v/, '').replace(/-r/, 'r');
}

function progress(label) {
	var number = E('span', { 'class': 'ae-num' }, '0%');
	var bar = E('progress', { 'max': '100', 'value': '0', 'aria-label': label });
	return { node: E('div', { 'class': 'ae-update-progress' }, [E('div', {}, [label, ' ', number]), bar]),
		set: function(value) {
			var percent = Math.max(0, Math.min(100, Number(value) || 0));
			number.textContent = percent + '%'; bar.value = percent;
		} };
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,
	render: function() {
		document.body.classList.add('gozarbin-page');
		var current = E('bdi', { 'class': 'ae-version-value' }, '—');
		var headerVersion = E('bdi', { 'class': 'ae-version ae-num' }, '—');
		var latest = E('bdi', { 'class': 'ae-version-value' }, '—');
		var finalVersion = E('bdi', { 'class': 'ae-version-value' }, '—');
		var status = E('div', { 'class': 'ae-update-state ae-inline-message', 'role': 'status', 'aria-live': 'polite' }, _('برای بررسی انتشار جدید GitHub، دکمهٔ بررسی را بزنید.'));
		var transfer = E('div', { 'class': 'ae-transfer' });
		var download = progress(_('درصد دانلود'));
		var installProgress = progress(_('پیشرفت مراحل نصب'));
		var busy = false;
		var releaseState = E('span', { 'class': 'ae-release-state' });
		var labels = {
			idle: _('آمادهٔ بررسی'), starting: _('در حال آماده‌سازی…'), checking: _('در حال بررسی GitHub…'),
			available: _('نسخهٔ جدید آمادهٔ دریافت است'), current: _('نسخهٔ نصب‌شده به‌روز است'),
			downloading: _('در حال دریافت از GitHub…'), installing: _('در حال نصب و بررسی بسته‌ها…'),
			done: _('به‌روزرسانی با موفقیت انجام شد.'), error: _('به‌روزرسانی ناموفق بود؛ اتصال و فضای خالی روتر را بررسی کنید.')
		};
		var check, install;
		function failure(error) {
			var message = String(error && error.message || '');
			if ((error && error.name === 'PermissionError') || /permission denied|access denied/i.test(message))
				status.textContent = _('مجوز نشست فعلی به‌روز نیست. از LuCI خارج شوید و دوباره وارد شوید؛ اگر خطا باقی ماند، سرویس rpcd را بازخوانی کنید.');
			else if (busy && /Object not found|NetworkError|Failed to fetch|timed out|aborted/i.test(message))
				status.textContent = _('سرویس‌های رابط در حال بازخوانی هستند؛ وضعیت دوباره بررسی می‌شود…');
			else status.textContent = message || labels.error;
		}
		function apply(state) {
			busy = ['starting', 'checking', 'downloading', 'installing'].indexOf(state.state) >= 0;
			current.textContent = version(state.current);
			headerVersion.textContent = version(state.current);
			latest.textContent = ['starting', 'checking'].indexOf(state.state) >= 0 || state.detail === 'network' ? '—' : version(state.latest);
			finalVersion.textContent = version(state.final);
			status.textContent = labels[state.state] || labels.idle;
			releaseState.textContent = state.state === 'available' ? _('نسخهٔ جدید آماده است') : state.state === 'current' ? _('آخرین نسخه نصب است') : '';
			if (state.detail === 'space') status.textContent = _('فضای موقت کافی برای دریافت و باز کردن بسته وجود ندارد.');
			if (state.detail === 'network') status.textContent = _('ارتباط با GitHub پس از چند تلاش برقرار نشد؛ اتصال اینترنت و DNS روتر را بررسی کنید و دوباره دکمهٔ بررسی را بزنید. آخرین نسخه تأیید نشده است.');
			if (state.detail === 'version') status.textContent = _('نصب تمام شد اما نسخهٔ نصب‌شده با نسخهٔ مقصد مطابقت ندارد.');
			download.set(state.download_percent);
			installProgress.set(state.install_percent);
			transfer.textContent = state.method === 'delta' ? _('دریافت تفاضلی؛ استفاده از بخش‌های مشترک نسخهٔ قبلی')
				: state.method === 'full' ? _('دریافت کامل بستهٔ مشترک گذربین و LuCI') : '';
			if (Number(state.total) > 0) transfer.appendChild(E('bdi', { 'class': 'ae-num' },
				' — ' + (Math.min(Number(state.downloaded) || 0, Number(state.total)) / 1048576).toFixed(2) + ' / ' + (Number(state.total) / 1048576).toFixed(2) + ' MB'));
			check.disabled = busy;
			install.disabled = busy || state.state !== 'available';
		}
		function refresh() {
			return fs.exec('/usr/bin/gozarbinctl', ['update', 'status']).then(function(result) {
				if (result.code !== 0) throw new Error(result.stderr || labels.error);
				apply(JSON.parse(result.stdout || '{}'));
			}).catch(failure);
		}
		function start(action) {
			busy = true; check.disabled = true; install.disabled = true;
			status.textContent = labels.starting;
			return fs.exec('/usr/bin/gozarbinctl', ['update', action]).then(function(result) {
				if (result.code !== 0) throw new Error(result.stderr || labels.error);
				return refresh();
			}).catch(function(error) { failure(error); busy = false; check.disabled = false; });
		}
		check = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-neutral',
			'click': ui.createHandlerFn(this, function() { return start('check'); }) }, _('بررسی نسخهٔ جدید'));
		install = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-apply', 'disabled': true,
			'click': ui.createHandlerFn(this, function() { return start('install'); }) }, _('به‌روزرسانی'));
		function row(label, value) { return E('div', { 'class': 'ae-version-row' }, [E('strong', {}, label), value]); }
		poll.add(refresh, 1);
		refresh();
		return E('div', { 'class': 'gozarbin-rtl', 'dir': i18n.dir(), 'lang': i18n.get() }, [
			E('link', { 'rel': 'stylesheet', 'href': L.resource('view/gozarbin/gozarbin.css') }),
			E('div', { 'class': 'ae-hero' }, [E('div', { 'class': 'ae-brand' }, [E('h2', {}, [_('گذربین'), headerVersion]),
				E('p', {}, _('دوست روزهای سخت اینترنتی در روتر شما'))]), appearance.controls()]),
			appearance.nav('update'),
			E('section', { 'class': 'ae-update' }, [
				E('h3', {}, _('به‌روزرسانی برنامه')),
				E('div', { 'class': 'ae-app-row' }, [
					E('strong', {}, _('گذربین')),
					E('div', { 'class': 'ae-app-versions' }, [
						E('span', { 'class': 'ae-installed-version' }, [E('small', {}, _('نسخهٔ نصب‌شده')), current]),
						E('span', { 'class': 'ae-published-version' }, [E('small', {}, _('آخرین بررسی GitHub')), latest]), releaseState]),
					E('div', { 'class': 'ae-actions' }, [check, install])]),
				status, transfer, download.node, installProgress.node,
				row(_('نسخهٔ نهایی پس از نصب'), finalVersion),
				E('p', {}, _('در اولین به‌روزرسانی یا نبود بخش مشترک کافی، بستهٔ کامل دریافت می‌شود. درصد نصب بر اساس پایان مراحل نصب بسته‌ها، بررسی نسخه و راه‌اندازی سرویس است. تنظیمات حفظ می‌شوند.'))
			]), appearance.footer()
		]);
	}
});
