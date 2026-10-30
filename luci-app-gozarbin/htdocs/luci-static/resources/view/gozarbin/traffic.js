/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require baseclass';
'require view.gozarbin.appearance as appearance';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;

function size(bytes) {
	var n = Math.max(0, Number(bytes) || 0), units = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
	while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
	return n.toFixed(i && n < 100 ? 2 : 0) + ' ' + units[i];
}

function gigabytes(bytes) {
	return (Math.max(0, Number(bytes) || 0) / 1000000000).toFixed(2);
}

return baseclass.extend({
	create: function() {
		var days = 1, history = { hours: [] }, buttons = [];
		var note = E('p', { 'class': 'ae-traffic-note' });
		var chart = E('div', { 'class': 'ae-traffic-chart', 'role': 'img', 'aria-label': _('نمودار مصرف ارسال و دریافت') });
		var up = E('bdi', { 'class': 'ae-traffic-up' }, '—');
		var down = E('bdi', { 'class': 'ae-traffic-down' }, '—');
		var total = E('bdi', {}, '—');
		var upload = E('bdi', {}, '—'), download = E('bdi', {}, '—');
		function metric(label, value) { return E('div', {}, [E('span', {}, label), value]); }
		function draw() {
			var now = Number(history.time) || Math.floor(Date.now() / 1000);
			var step = days === 1 ? 3600 : 86400, count = days === 1 ? 24 : days;
			// The daily bins begin at midnight in Tehran (UTC+03:30).
			var offset = 12600;
			var end = Math.floor((now + offset) / step) * step - offset;
			var start = end - (count - 1) * step, values = [];
			for (var i = 0; i < count; i++) values.push([0, 0]);
			(history.hours || []).forEach(function(row) {
				var at = Math.floor((Number(row[0]) - start) / step);
				if (at >= 0 && at < count) { values[at][0] += Number(row[1]) || 0; values[at][1] += Number(row[2]) || 0; }
			});
			var sumUp = 0, sumDown = 0, peak = 1;
			values.forEach(function(row) { sumUp += row[0]; sumDown += row[1]; peak = Math.max(peak, row[0] + row[1]); });
			upload.textContent = gigabytes(sumUp); download.textContent = gigabytes(sumDown); total.textContent = gigabytes(sumUp + sumDown);
			chart.replaceChildren();
			values.forEach(function(row, i) {
				var label = new Intl.DateTimeFormat(i18n.locale(), { timeZone: 'Asia/Tehran', month: 'short', day: 'numeric',
					hour: days === 1 ? '2-digit' : undefined }).format(new Date((start + i * step) * 1000));
				var a = E('span', { 'class': 'ae-traffic-download' }); a.style.height = (row[1] / peak * 100) + '%';
				var b = E('span', { 'class': 'ae-traffic-upload' }); b.style.height = (row[0] / peak * 100) + '%';
				chart.appendChild(E('div', { 'class': 'ae-traffic-column', 'title': label + ' — ' + _('دریافت: ') + size(row[1]) + '، ' + _('ارسال: ') + size(row[0]) }, [a, b]));
			});
			note.textContent = (days === 1 ? _('۲۴ ساعت اخیر؛ هر ستون یک ساعت') : _('مصرف روزانه در بازهٔ انتخاب‌شده')) +
				' · ' + _('تاریخچه از زمان فعال‌شدن ثبت می‌شود؛ داده‌ای برای روزهای قبل ساخته نمی‌شود.');
			buttons.forEach(function(button) { button.setAttribute('aria-pressed', String(Number(button.dataset.days) === days)); });
		}
		[1, 7, 30].forEach(function(value, index) {
			var button = E('button', { 'type': 'button', 'class': 'ae-range-button', 'data-days': value,
				'title': value + _(' روز') }, i18n.get() === 'fa' ? ['۱ر', '۷ر', '۳۰ر'][index] : ['1d', '1w', '1m'][index]);
			button.addEventListener('click', function() { days = value; draw(); }); buttons.push(button);
		});
		var node = E('section', { 'class': 'ae-traffic ae-card' }, [
			E('h3', { 'class': 'ae-card-label' }, [appearance.icon('traffic'), E('span', {}, _('مصرف (گیگابایت)'))]),
			E('div', { 'class': 'ae-traffic-metrics' }, [metric(_('ارسال'), upload), metric(_('دریافت'), download), metric(_('مجموع'), total)]),
			E('div', { 'class': 'ae-ranges', 'role': 'group', 'aria-label': _('مصرف ترافیک') }, buttons),
			E('details', { 'class': 'ae-traffic-details' }, [
				E('summary', {}, _('نمودار مصرف ارسال و دریافت')), chart, note,
				E('div', { 'class': 'ae-traffic-live' }, [metric(_('↓ دریافت لحظه‌ای'), down), metric(_('↑ ارسال لحظه‌ای'), up)])
			])
		]);
		draw();
		return { node: node, history: function(value) { history = value || { hours: [] }; draw(); },
			update: function(data, rates) {
				var valid = data.accounting !== false && data.counters !== false;
				up.textContent = valid ? size(rates.upload) + '/s' : '—';
				down.textContent = valid ? size(rates.download) + '/s' : '—';
				if (data.accounting === false) note.textContent = _('شمارش ترافیک خاموش است؛ در تنظیمات پیشرفته فعال کنید.');
			}
		};
	}
});
