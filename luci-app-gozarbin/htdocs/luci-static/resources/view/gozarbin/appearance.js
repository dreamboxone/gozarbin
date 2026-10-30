/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require baseclass';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;

return baseclass.extend({
	icon: function(name) {
		var paths = {
			home: 'M3 11l9-8 9 8 M5 10v11h5v-7h4v7h5V10',
			network: 'M9 3h6v6H9z M2 17h6v5H2z M16 17h6v5h-6z M12 9v4 M5 17v-4h14v4',
			routing: 'M4 4h6v6H4z M14 14h6v6h-6z M7 10v7h7 M10 7h7v7',
			sliders: 'M4 3v18 M12 3v18 M20 3v18 M1 8h6 M9 16h6 M17 8h6',
			settings: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M5 19l2-2 M17 7l2-2',
			refresh: 'M21 3v6h-6 M3 21v-6h6 M3 11a9 9 0 0 1 15-7l3 3 M21 13a9 9 0 0 1-15 7l-3-3',
			pulse: 'M3 12h4l3-8 4 16 3-8h4',
			server: 'M4 3h16v7H4z M4 14h16v7H4z M7 6.5h.01 M7 17.5h.01 M11 6.5h6 M11 17.5h6',
			device: 'M3 5h18v12H3z M8 21h8 M12 17v4',
			shield: 'M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6z M8 12l3 3 5-6',
			traffic: 'M7 3v17 M3 16l4 4 4-4 M17 21V4 M13 8l4-4 4 4',
			send: 'M21 3L3 10l7 4 4 7z M10 14L21 3',
			code: 'M8 6l-6 6 6 6 M16 6l6 6-6 6 M14 3l-4 18',
			book: 'M4 3h7a3 3 0 0 1 3 3v15a4 4 0 0 0-3-2H4z M14 6a3 3 0 0 1 3-3h4v16h-4a4 4 0 0 0-3 2 M7 7h3 M7 11h3'
		};
		var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
		var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
		svg.setAttribute('viewBox', '0 0 24 24');
		svg.setAttribute('class', 'ae-icon');
		svg.setAttribute('aria-hidden', 'true');
		svg.setAttribute('fill', 'none');
		svg.setAttribute('stroke', 'currentColor');
		svg.setAttribute('stroke-width', '1.8');
		svg.setAttribute('stroke-linecap', 'round');
		svg.setAttribute('stroke-linejoin', 'round');
		path.setAttribute('d', paths[name] || paths.device);
		svg.appendChild(path);
		if (name === 'refresh') {
			path.setAttribute('d', 'M21 3v6h-6 M3 11a9 9 0 0 1 15-7l3 3');
			path.setAttribute('stroke', '#06b6d4');
			var other = path.cloneNode();
			other.setAttribute('d', 'M3 21v-6h6 M21 13a9 9 0 0 1-15 7l-3-3');
			other.setAttribute('stroke', '#10b981');
			svg.appendChild(other);
		}
		return svg;
	},
	logo: function() {
		return E('img', { 'class': 'ae-logo', 'src': L.resource('view/gozarbin/logo.png'),
			'alt': '', 'width': '52', 'height': '52' });
	},
	controls: function() {
		return E('div', { 'class': 'ae-hero-controls' }, [i18n.selector(), this.toggle()]);
	},
	footer: function() {
		return E('footer', { 'class': 'ae-footer' }, [
			E('div', { 'class': 'ae-footer-brand' }, [this.logo(), E('strong', {}, 'Gozarbin')]),
			E('div', {}, ['Gozarbin · Copyright © 2026 dreamboxone · GNU AGPLv3 · ', _('بدون ضمانت')]),
			E('a', { 'href': 'https://t.me/routekernel1', 'target': '_blank', 'rel': 'noopener noreferrer' },
				[this.icon('send'), E('bdi', {}, 'Telegram · t.me/routekernel1')]),
			E('a', { 'href': 'https://github.com/dreamboxone/gozarbin', 'target': '_blank', 'rel': 'noopener noreferrer' },
				[this.icon('code'), _('کد منبع')])
		]);
	},
	nav: function(active) {
		return E('nav', { 'class': 'ae-tabs', 'aria-label': _('بخش‌های گذربین') }, [
			['settings', _('خانه'), 'home', 'general'],
			['routing', _('مدیریت قوانین'), 'routing', 'routing'],
			['advanced', _('شبکه'), 'network', 'advanced'],
			['aether', _('تنظیمات دیگر'), 'sliders', 'aether'],
			['reports', _('گزارش'), 'book', 'reports'],
			['update', _('به‌روزرسانی'), 'refresh']
		].map(function(item) {
			return E('a', { 'class': 'ae-tab' + (active === item[0] ? ' ae-tab-on' : ''),
				'data-section': item[3] || '',
				'href': L.url('admin/services/gozarbin/' + (item[0] === 'update' ? 'update' : 'settings')) + (item[3] ? '#' + item[3] : ''),
				'aria-current': active === item[0] ? 'page' : 'false' }, [this.icon(item[2]), E('span', {}, item[1])]);
		}, this));
	},
	mainSwitch: function(root) {
		root.querySelectorAll('input[type="checkbox"]').forEach(function(control) {
			control.setAttribute('role', 'switch');
			function update() { control.setAttribute('aria-checked', String(control.checked)); }
			control.addEventListener('change', update); update();
		});
		var input = root.querySelector('[id="cbid.gozarbin.main.enabled"] input[type="checkbox"], input[data-widget-id="widget.cbid.gozarbin.main.enabled"]');
		if (!input) return;
		input.classList.add('ae-main-switch');
		input.setAttribute('role', 'switch');
		function update() { input.setAttribute('aria-checked', String(input.checked)); }
		input.addEventListener('change', update); update(); return input;
	},
	bindNavigation: function(root) {
		var names = ['general', 'routing', 'advanced', 'aether', 'reports'];
		function activate(section) {
			if (names.indexOf(section) < 0) section = 'general';
			var tabs = root.querySelectorAll('.cbi-tabmenu li a');
			if (tabs[names.indexOf(section)]) tabs[names.indexOf(section)].click();
			root.querySelectorAll('.ae-tabs a[data-section]').forEach(function(link) {
				var selected = link.dataset.section === section;
				link.classList.toggle('ae-tab-on', selected);
				link.setAttribute('aria-current', selected ? 'page' : 'false');
				if (selected) {
					var heading = root.querySelector('.cbi-map > h2');
					if (heading && heading.firstChild && heading.firstChild.nodeType === 3) heading.firstChild.textContent = section === 'general' ? _('تنظیمات پایه') : link.textContent;
				}
			});
		}
		root.querySelectorAll('.ae-tabs a[data-section]').forEach(function(link) {
			if (!link.dataset.section) return;
			link.addEventListener('click', function(event) {
				event.preventDefault();
				window.history.replaceState(null, '', link.href);
				activate(link.dataset.section);
			});
		});
		root.classList.add('ae-main-navigation');
		window.setTimeout(function() { activate(window.location.hash.slice(1)); }, 0);
	},
	/* Help popovers follow Zirgozar's label, click and keyboard behavior. */
	help: function(root) {
		var active = null, connected = false;
		function close() {
			if (!active) return;
			active.open = false;
			active.querySelector('summary').setAttribute('aria-expanded', 'false');
			active = null;
		}
		function enhance() {
			root.querySelectorAll('.cbi-value-description,.cbi-map-descr,.ae-help-text').forEach(function(desc) {
				if (desc.closest('.ae-help') || !desc.textContent.trim()) return;
				var row = desc.closest('.cbi-value'), label = row && row.querySelector('.cbi-value-title');
				if (!label && desc.classList.contains('cbi-map-descr')) label = desc.parentElement.querySelector('h2');
				if (!label && desc.classList.contains('ae-help-text')) label = desc.closest('section').querySelector('h3');
				var help = E('details', { 'class': 'ae-help' });
				var summary = E('summary', { 'aria-label': _('راهنمای گزینه'), 'aria-expanded': 'false' }, i18n.get() === 'fa' ? '؟' : '?');
				help.appendChild(summary);
				desc.classList.add('ae-help-content');
				if (label) label.appendChild(help); else desc.parentElement.insertBefore(help, desc);
				help.appendChild(desc);
				summary.addEventListener('click', function(event) {
					event.preventDefault(); event.stopPropagation();
					var opening = !help.open; close();
					if (!opening) return;
					help.open = true; active = help; summary.setAttribute('aria-expanded', 'true');
					var anchor = summary.getBoundingClientRect(), box = desc.getBoundingClientRect();
					desc.style.left = Math.max(16, Math.min(i18n.get() === 'fa' ? anchor.right - box.width : anchor.left, window.innerWidth - box.width - 16)) + 'px';
					desc.style.top = Math.max(16, anchor.bottom + 8 + box.height <= window.innerHeight - 16 ? anchor.bottom + 8 : anchor.top - box.height - 8) + 'px';
				});
			});
		}
		function outside(event) { if (active && !active.contains(event.target)) close(); }
		function escape(event) { if (event.key === 'Escape' && active) { var summary = active.querySelector('summary'); close(); summary.focus(); } }
		var observer = new MutationObserver(function() {
			if (root.isConnected) connected = true;
			else if (connected) {
				close(); observer.disconnect(); document.removeEventListener('click', outside);
				document.removeEventListener('keydown', escape); document.removeEventListener('scroll', outside, true);
				window.removeEventListener('resize', close); return;
			}
			enhance();
		});
		enhance(); observer.observe(document.body, { 'childList': true, 'subtree': true });
		document.addEventListener('click', outside); document.addEventListener('keydown', escape);
		document.addEventListener('scroll', outside, true); window.addEventListener('resize', close);
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
