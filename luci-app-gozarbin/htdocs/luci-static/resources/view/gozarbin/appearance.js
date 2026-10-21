/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require baseclass';

return baseclass.extend({
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
