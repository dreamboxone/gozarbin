/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require baseclass';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;

return baseclass.extend({
	controls: function() {
		return E('div', { 'class': 'ae-hero-controls' }, [i18n.selector(), this.toggle()]);
	},
	footer: function() {
		return E('footer', { 'class': 'ae-footer' }, E('a', {
			'href': 'https://t.me/routekernel1', 'target': '_blank', 'rel': 'noopener noreferrer'
		}, [_('گروه تلگرام'), ' · ', E('bdi', {}, '@routekernel1')]));
	},
	nav: function(active) {
		return E('nav', { 'class': 'ae-tabs', 'aria-label': _('بخش‌های گذربین') }, [
			['settings', _('تنظیمات و وضعیت')], ['update', _('به‌روزرسانی')]
		].map(function(item) {
			return E('a', { 'class': 'ae-tab' + (active === item[0] ? ' ae-tab-on' : ''),
				'href': L.url('admin/services/gozarbin/' + item[0]), 'aria-current': active === item[0] ? 'page' : 'false' }, item[1]);
		}));
	},
	toggle: function() {
		var saved;
		try { saved = window.localStorage.getItem('gozarbin-theme'); } catch (e) {}
		var dark = saved === 'dark' || (saved !== 'light' && window.matchMedia('(prefers-color-scheme: dark)').matches);
		var button = E('button', { 'type': 'button', 'class': 'ae-theme-toggle', 'aria-label': _('تغییر حالت روز و شب') });
		function apply() {
			document.body.classList.toggle('gozarbin-dark', dark);
			button.textContent = dark ? _('☀ حالت روز') : _('☾ حالت شب');
			button.setAttribute('aria-pressed', String(dark));
		}
		button.addEventListener('click', function() {
			dark = !dark;
			try { window.localStorage.setItem('gozarbin-theme', dark ? 'dark' : 'light'); } catch (e) {}
			apply();
		});
		apply();
		return button;
	}
});
