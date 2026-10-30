/* SPDX-License-Identifier: AGPL-3.0-only
 * Copyright (C) 2026 dreamboxone
 */
'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require poll';
'require uci';
'require view.gozarbin.appearance as appearance';
'require view.gozarbin.traffic as trafficui';
'require view.gozarbin.i18n as i18n';

var _ = i18n.tr;

var GEO_DEFAULTS = {
	geoip_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geoip-ir.srs',
	geosite_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs',
	geosite_ads_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-category-ads-all.srs'
};

/* Written by the init script into /var/run/gozarbin/transparent-off. */
var REASONS = {
	passwall2: _('حالت شفاف اجرا نشده چون Passwall2 فعال است'),
	dependencies: _('حالت شفاف اجرا نشده چون یک پیش‌نیاز نصب نیست'),
	singbox: _('حالت شفاف اجرا نشده چون هستهٔ sing-box نصب نیست')
};

/* The non-Iranian exit, as traffic.sh reports it. "off" says nothing. */
var UNBLOCK = {
	starting: _('خروجی غیرایرانی: در حال اتصال از راه Tor'),
	ready: _('خروجی غیرایرانی: آماده'),
	down: _('خروجی غیرایرانی: قطع است')
};

/* The countries Psiphon usually offers as an exit. The log lists what is on
 * offer right now, and anything there that is missing here is added by code. */
var COUNTRIES = {
	AT: _('اتریش'), AU: _('استرالیا'), BE: _('بلژیک'), BG: _('بلغارستان'),
	CA: _('کانادا'), CH: _('سوئیس'), CZ: _('چک'), DE: _('آلمان'),
	DK: _('دانمارک'), EE: _('استونی'), ES: _('اسپانیا'), FI: _('فنلاند'),
	FR: _('فرانسه'), GB: _('بریتانیا'), HU: _('مجارستان'), IE: _('ایرلند'),
	IN: _('هند'), IT: _('ایتالیا'), JP: _('ژاپن'), LV: _('لتونی'),
	NL: _('هلند'), NO: _('نروژ'), PL: _('لهستان'), RO: _('رومانی'),
	RS: _('صربستان'), SE: _('سوئد'), SG: _('سنگاپور'), SK: _('اسلواکی'),
	US: _('آمریکا')
};

var PSIPHON = {
	chain: _('Psiphon داخل WARP'),
	reverse: _('WARP از راه Psiphon'),
	only: _('فقط Psiphon')
};

var MEGABYTE = 1024 * 1024;

function ltr(text) {
	return E('span', { 'class': 'ae-num' }, String(text));
}

function pingMilliseconds(value) {
	var match = String(value || '').trim().match(/^([0-9.]+)\s*(s|ms|us|µs)$/i);
	if (!match) return '';
	var number = Number(match[1]);
	if (!isFinite(number)) return '';
	var unit = match[2].toLowerCase();
	if (unit === 's') number *= 1000;
	else if (unit === 'us' || unit === 'µs') number /= 1000;
	return String(Math.max(1, Math.round(number)));
}

function countryFlag(country) {
	var code = String(country || '').trim().toUpperCase();
	if (!/^[A-Z]{2}$/.test(code)) return '';
	return String.fromCodePoint(code.charCodeAt(0) + 127397, code.charCodeAt(1) + 127397);
}

function countryName(country) {
	var code = String(country || '').trim().toUpperCase();
	var name = COUNTRIES[code];
	return countryFlag(code) + ' ' + (name ? name + ' (' + code + ')' : code);
}

/* "DE NL US" from the log, as the codes it names. */
function regionCodes(text) {
	return String(text || '').toUpperCase().split(/[\s,]+/).filter(function(code) {
		return /^[A-Z]{2}$/.test(code);
	});
}

/* The figure is its own left-to-right island so its digits stay in order, and
 * the unit is ordinary right-to-left text beside it. Written as one string the
 * whole thing becomes an island and the number lands on the wrong side. */
function measure(number, unit) {
	return E('span', {}, [ ltr(number), ' ', unit ]);
}

function megabytes(value) {
	var mb = (Number(value) || 0) / MEGABYTE;
	return mb >= 100 ? mb.toFixed(0) : mb.toFixed(mb >= 10 ? 1 : 2);
}

function amount(value) {
	return measure(megabytes(value), _('مگابایت'));
}

function rate(value) {
	return measure(megabytes(value), _('مگابایت بر ثانیه'));
}

function count(value) {
	return measure(Number(value) || 0, _('بسته'));
}

function duration(seconds) {
	var s = Math.max(0, Math.floor(Number(seconds) || 0));
	var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600);
	var m = Math.floor(s % 3600 / 60);
	if (d > 0) return d + _(' روز و ') + h + _(' ساعت');
	if (h > 0) return h + _(' ساعت و ') + m + _(' دقیقه');
	if (m > 0) return m + _(' دقیقه و ') + (s % 60) + _(' ثانیه');
	return s + _(' ثانیه');
}

function parse(result, fallback) {
	try { return JSON.parse((result && result.stdout) || '{}'); }
	catch (e) { return fallback || {}; }
}

/* Operation feedback stays below the controls on every LuCI theme. */
function notify(message, kind) {
	var target = document.querySelector('.ae-action-messages');
	if (!target) return null;
	target.replaceChildren(E('div', {
		'class': 'ae-inline-message ae-message-' + (kind || 'info'),
		'role': kind === 'error' ? 'alert' : 'status', 'dir': i18n.dir()
	}, [E('span', {}, message), E('button', { 'type': 'button', 'class': 'ae-message-close', 'aria-label': _('بستن پیام'),
		'click': function() { target.replaceChildren(); } }, '×')]));
	return target;
}
function card(label, klass, icon) {
	var value = E('div', { 'class': 'ae-card-value' }, '—');
	var note = E('div', { 'class': 'ae-card-note' }, '');
	var bar = E('div', { 'class': 'ae-bar' }, E('span', {}));
	var node = E('div', { 'class': 'ae-card ' + (klass || '') }, [
		E('div', { 'class': 'ae-card-label' }, [appearance.icon(icon || 'device'), E('span', {}, label)]), value, note
	]);
	if (klass === 'ae-card-up' || klass === 'ae-card-down') node.appendChild(bar);
	return { node: node, value: value, note: note, bar: bar.firstChild };
}

function badge(text, state) {
	return E('span', { 'class': 'ae-badge ae-badge-' + state }, text);
}

return view.extend({
	load: function() {
		var soft = function() { return { stdout: '{}' }; };
		return Promise.all([
			fs.exec('/usr/libexec/gozarbin/dashboard.sh').catch(soft),
			uci.load('gozarbin'),
			fs.read('/usr/share/gozarbin/core-options.json').catch(function() { return '{}'; })
		]).then(function(results) {
			var snapshot = parse(results[0]);
			return ['proxy', 'system', 'deps', 'traffic', 'core', 'tunnel'].map(function(key) {
				return { stdout: JSON.stringify(snapshot[key] || {}) };
			}).concat([results[1], results[2], { stdout: JSON.stringify(snapshot.connectivity || {}) }]);
		});
	},

	renderDashboard: function(system, passwall, deps, traffic, tunnel) {
		var self = this;
		this.dependencyState = deps || {};
		var service = card(_('وضعیت'), '', 'pulse');
		this.proxyState = passwall;
		this.conflictMessage = E('div', { 'class': 'ae-conflict-message' });
		service.node.insertBefore(this.conflictMessage, service.value);
		service.node.insertBefore(E('div', { 'class': 'ae-action-messages', 'aria-live': 'polite' }), service.value);
		var server = card(_('سرور و اسکن'), '', 'server');
		var usage = trafficui.create();
		this.traffic = usage;
		var build = card(_('نوع دستگاه'), 'ae-card-device', 'device');
		var health = card(_('پیش‌نیازها'), 'ae-card-health', 'shield');

		build.value.textContent = '';
		build.value.appendChild(E('span', {}, system.model || _('نامشخص')));
		build.note.appendChild(ltr([
			system.release || '', system.arch || ''
		].filter(Boolean).join(' • ')));

		var kernelOk = system.tproxy && system.socket && system.nftables;
		health.value.textContent = '';
		var origins = {
			own: _('هسته گذربین'),
			system: _('هستهٔ sing-box سیستم')
		};
		health.value.appendChild(badge(
			system.singbox ? 'sing-box ' + (system.singbox_version || '') : _('هستهٔ sing-box نصب نیست'),
			system.singbox ? 'ok' : 'bad'));
		if (origins[system.singbox_origin])
			health.value.appendChild(badge(origins[system.singbox_origin], 'ok'));
		health.value.appendChild(badge(
			kernelOk ? _('ماژول‌های TProxy کامل') : _('ماژول‌های TProxy ناقص'),
			kernelOk ? 'ok' : 'bad'));
		health.value.appendChild(badge(
			system.tun ? _('TUN آماده') : _('TUN نصب نیست'), system.tun ? 'ok' : 'warn'));
		health.value.appendChild(badge(
			system.psiphon ? _('Psiphon نصب') : _('Psiphon نصب نیست'), system.psiphon ? 'ok' : 'warn'));

		if (deps && deps.complete === false && deps.missing)
			health.note.textContent = _('نصب نشده: ') + deps.missing;
		else
			health.note.textContent = _('همهٔ بسته‌های لازم نصب هستند.');

		var dash = E('div', { 'class': 'ae-dash' }, [
			service.node, server.node, build.node, usage.node, health.node
		]);

		this.state = { time: 0, upload: 0, download: 0, peak: 1 };
		this.cards = { service: service, server: server };
		this.applyTraffic(traffic);
		this.showProxyConflict();
		this.applyTunnel(tunnel);
		poll.add(function() {
			return Promise.all([
				fs.exec('/usr/libexec/gozarbin/traffic.sh').catch(function() { return null; }),
				fs.exec('/usr/libexec/gozarbin/tunnel.sh').catch(function() { return null; })
			]).then(function(results) {
				if (results[0]) self.applyTraffic(parse(results[0]));
				if (results[1]) self.applyTunnel(parse(results[1]));
			});
		}, 3);
		var refreshHistory = function() {
			return fs.exec('/usr/libexec/gozarbin/history.sh', ['report']).then(function(result) {
				if (result.code === 0) usage.history(parse(result));
			}).catch(function() {});
		};
		refreshHistory();
		poll.add(refreshHistory, 30);
		poll.add(function() {
			return fs.exec('/usr/libexec/gozarbin/connectivity.sh', ['status']).then(function(result) {
				if (result.code === 0) { self.connectivity = parse(result); self.updateConnectionNote(); }
			}).catch(function() {});
		}, 5);
		return dash;
	},

	/* Which server the tunnel is on and how it got there. Without this the page
	 * said nothing about the one thing the program exists to do, so a working
	 * tunnel and a dead one looked identical. */
	applyTunnel: function(tunnel) {
		if (!this.cards || !this.cards.server || !tunnel) return;
		var card = this.cards.server;
		var states = {
			connected: { text: _('متصل'), dot: 'ae-dot-on' },
			scanning: { text: _('در حال اسکن…'), dot: 'ae-dot-warn' },
			retrying: { text: _('اسکن ناموفق، تلاش دوباره…'), dot: '' },
			verifying: { text: _('بررسی سرور قبلی…'), dot: 'ae-dot-warn' },
			starting: { text: _('در حال شروع…'), dot: 'ae-dot-warn' },
			psiphon: { text: _('در حال اتصال Psiphon…'), dot: 'ae-dot-warn' },
			failed: { text: tunnel.detail === 'psiphon' ? _('Psiphon وصل نشد') : _('سروری پیدا نشد'), dot: '' },
			stopped: { text: _('خاموش'), dot: '' }
		};
		var shown = states[tunnel.state] || states.stopped;
		var fails = Number(tunnel.fails) || 0;
		var udpProtocol = (tunnel.protocol === 'wg' || tunnel.protocol === 'gool');

		card.value.textContent = '';
		card.value.appendChild(E('span', { 'class': 'ae-dot ' + shown.dot }));
		card.value.appendChild(document.createTextNode(shown.text));
		if (tunnel.gateway && tunnel.state !== 'stopped') {
			card.value.appendChild(E('div', { 'class': 'ae-server' }, ltr(tunnel.gateway)));
		}

		var note = [];
		var psiphon = PSIPHON[tunnel.psiphon];
		if (tunnel.state === 'connected') {
			if (tunnel.psiphon !== 'only')
				note.push(tunnel.source === 'cache'
					? _('از سرور ذخیره‌شده، بدون اسکن')
					: _('از اسکن تازه'));
			if (psiphon) note.push(psiphon);
			if (tunnel.transport) note.push(tunnel.transport);
			/* Psiphon is asked, not told: a country it has no server in right
			 * now is quietly replaced by one it has. With WARP dialled through
			 * Psiphon the exit is Cloudflare's, which places it on its own. */
			if (psiphon && tunnel.psiphon !== 'reverse' && tunnel.psiphon_region && tunnel.country &&
			    tunnel.psiphon_region.toUpperCase() !== tunnel.country.toUpperCase())
				note.push(_('کشور درخواستی ') + countryName(tunnel.psiphon_region) + _(' در دسترس نبود'));
		} else if (tunnel.state === 'psiphon') {
			if (psiphon) note.push(psiphon);
			if (tunnel.psiphon_region) note.push(_('کشور درخواستی: ') + countryName(tunnel.psiphon_region));
			note.push(_('اتصال اول Psiphon ممکن است تا سه دقیقه طول بکشد'));
		} else if (tunnel.state === 'failed' && tunnel.detail === 'psiphon') {
			note.push(_('اگر Psiphon روی این شبکه وصل نمی‌شود، شیوهٔ اتصال Psiphon را CDN کنید'));
		} else if (tunnel.state === 'failed' || tunnel.state === 'retrying') {
			note.push(_('تا حالا ') + fails + _(' بار ناموفق'));
			/* WireGuard and WARP-in-WARP need their UDP ports through; MASQUE
			 * rides QUIC on 443, which is the one that usually survives. Saying
			 * which knob to turn beats a spinner that never stops. */
			if (udpProtocol && fails >= 2)
				note.push(_('پورت‌های UDP این پروتکل روی این شبکه باز نیستند — پروتکل را MASQUE کنید'));
			else if (fails >= 2)
				note.push(_('پروفایل استتار را gfw و حالت اسکن را thorough کنید'));
		} else if (tunnel.state === 'scanning') {
			note.push(_('چند دقیقه طول می‌کشد'));
		}
		card.note.textContent = note.join(' • ');
	},

	updateConnectionNote: function() {
		if (!this.cards) return;
		var note = this.cards.service.note, state = this.connectivity || {};
		note.replaceChildren();
		if (!this.serviceRunning) return;
		var ping = state.ping != null && Number.isFinite(Number(state.ping)) ? Math.max(0, Math.round(Number(state.ping))) + ' ms' : '—';
		note.appendChild(E('span', { 'class': 'ae-status-ping' }, [_('پینگ'), ': ', ltr(ping)]));
		if (/^[A-Z]{2}$/.test(state.country || ''))
			note.appendChild(E('span', { 'class': 'ae-status-country' }, countryName(state.country)));
	},

	applyTraffic: function(traffic) {
		if (traffic && typeof traffic.enabled === 'boolean') this.serviceEnabled = traffic.enabled;
		if (traffic && typeof traffic.running === 'boolean') {
			this.serviceKnown = true;
			this.serviceRunning = traffic.running;
			this.updateServiceToggle();
		}
		this.showProxyConflict();
		this.syncMainSwitch();
		if (!this.cards || !traffic) return;
		var cards = this.cards, previous = this.state;
		var running = traffic.running === true;
		var modes = { tproxy: _('پراکسی شفاف (TProxy)'), tun: _('حالت TUN'), socks: _('فقط SOCKS5') };

		cards.service.value.textContent = '';
		cards.service.value.appendChild(E('span', {
			'class': 'ae-dot ' + (running ? 'ae-dot-on' : (traffic.enabled ? 'ae-dot-warn' : ''))
		}));
		cards.service.value.appendChild(E('span', { 'class': running ? 'ae-service-running' : '' },
			running ? _('در حال اجرا') : (traffic.enabled ? _('روشن، بالا نیامده') : _('خاموش'))));
		this.updateConnectionNote();

		var upload = Number(traffic.upload) || 0, download = Number(traffic.download) || 0;
		var now = Number(traffic.time) || Math.floor(Date.now() / 1000);
		var span = previous.time ? now - previous.time : 0;
		/* The counters restart whenever the firewall rules are rebuilt; a drop
		 * means a reset, not negative throughput. */
		var upRate = span > 0 && upload >= previous.upload ? (upload - previous.upload) / span : 0;
		var downRate = span > 0 && download >= previous.download ? (download - previous.download) / span : 0;
		var peak = Math.max(previous.peak || 1, upRate, downRate, 1);

		this.traffic.update(traffic, { upload: upRate, download: downRate });

		this.state = { time: now, upload: upload, download: download, peak: peak };
	},

	/* Passwall2, Passwall and ShadowSocksR all read `mark & 0xff == 0xff` as
	 * "not mine", and their output chains otherwise pull every packet the router
	 * sends into their own proxy — Gozarbin's tunnel included, which then connects
	 * and carries nothing. There is no symptom to go on, so it is said here. */
	renderMarkNotice: function(passwall) {
		var self = this;
		var mark = uci.get('gozarbin', 'main', 'mark') || '0x0aff';
		if (!passwall.installed || /ff$/i.test(mark)) return E([]);
		return E('div', { 'class': 'ae-notice ae-notice-bad' }, [
			E('div', { 'class': 'ae-notice-text' }, [
				E('strong', {}, _('علامت فایروال با Passwall2 سازگار نیست')),
				E('div', {}, [
					_('علامت فعلی '), ltr(mark),
					_(' است. Passwall2 هر بسته‌ای را که روتر می‌فرستد به پراکسی خودش می‌برد مگر آنکه بایت آخر علامت ff باشد — با این علامت، تونل گذربین وصل می‌شود ولی هیچ ترافیکی از آن رد نمی‌شود.')
				])
			]),
			this.action(_('اصلاح علامت'), 'apply', function() {
				return fs.exec('/usr/bin/gozarbinctl', [ 'fix-mark' ]).then(function(result) {
					if (result.code === 0) notify(_('علامت فایروال به 0x0aff تغییر کرد و سرویس دوباره راه‌اندازی شد.'));
					else notify(_('تغییر علامت ناموفق بود: ') + (result.stderr || result.code), 'error');
				}).catch(function(error) { notify(_('اجرا نشد: ') + error.message, 'error'); });
			})
		]);
	},

	/* Silent unless there is something to act on. A router that is offline, or
	 * behind a blocked GitHub, or simply has not passed enough traffic for the
	 * check to have run, has nothing to be told about. */
	renderCoreNotice: function(system, core) {
		if (system.singbox && !(core && core.update)) return E([]);
		return E('div', { 'class': 'ae-notice' }, [
			E('span', {}, system.singbox ? _('نسخه جدید هسته سینگ باکس در دسترس است.') : _('حالت شفاف و TUN به هسته اختصاصی سینگ باکس نیاز دارند.')),
			E('a', { 'class': 'cbi-button cbi-button-apply', 'href': L.url('admin/services/gozarbin/update') }, _('به روز رسانی هسته سینگ باکس'))
		]);
	},

	action: function(label, style, handler) {
		var feedback = E('div', { 'class': 'ae-button-message', 'aria-live': 'polite' });
		var button = E('button', {
			'class': 'cbi-button cbi-button-' + style,
			'type': 'button',
			'click': ui.createHandlerFn(this, function() {
				return handler.apply(this, arguments);
			})
		}, label);
		return E('div', { 'class': 'ae-action-item' }, [button, feedback]);
	},

	showProxyConflict: function() {
		if (!this.conflictMessage) return;
		var self = this, state = this.proxyState || {};
		var enabled = this.blockedActivation || (this.mainSwitchIntent == null ? this.serviceEnabled : this.mainSwitchIntent);
		var services = [];
		if (state.zirgozar_active) services.push(_('زیرگذر اکنون فعال می باشد. گذربین نمی تواند همزمان با زیرگذر فعالیت کند. زیرگذر را غیرفعال کنید.'));
		if (state.active) services.push(_('Passwall2 اکنون فعال می باشد. گذربین نمی تواند همزمان با Passwall2 فعالیت کند. Passwall2 را غیرفعال کنید.'));
		var message = enabled && services.length ? services.join('\n') : '';
		this.conflictMessage.replaceChildren();
		if (!message) { this.dismissedConflict = ''; return; }
		if (this.dismissedConflict === message) return;
		this.conflictMessage.appendChild(E('div', { 'class': 'ae-inline-message ae-message-warning', 'role': 'status' }, [
			E('span', {}, message),
			E('button', { 'type': 'button', 'class': 'ae-message-close', 'aria-label': _('بستن پیام'), 'click': function() {
				self.dismissedConflict = message;
				self.conflictMessage.replaceChildren();
			} }, '×')
		]));
	},

	checkProxyConflict: function() {
		var self = this;
		return fs.exec('/usr/libexec/gozarbin/passwall2-detect.sh', ['--json']).then(function(result) {
			if (result.code !== 0) throw new Error(result.stderr || _('وضعیت سرویس دریافت نشد.'));
			self.proxyState = parse(result);
			self.showProxyConflict();
		}).catch(function(error) { notify(_('اجرا نشد: ') + error.message, 'error'); });
	},

	updateServiceToggle: function() {
		if (this.mainSwitchInput) this.mainSwitchInput.disabled = !!this.serviceBusy;
		if (!this.serviceToggle) return;
		this.serviceToggle.textContent = this.serviceBusy ? _('در حال انجام…') : this.serviceRunning ? _('توقف') : _('شروع');
		this.serviceToggle.disabled = !!this.serviceBusy || !this.serviceKnown;
		this.serviceToggle.className = 'cbi-button cbi-button-' + (this.serviceRunning ? 'reset' : 'apply');
		this.serviceToggle.setAttribute('aria-busy', String(!!this.serviceBusy));
	},

	runCoreAction: function(action) {
		var self = this;
		notify(_('در حال انجام…'));
		return fs.exec('/usr/libexec/gozarbin/aether-core.sh', [action]).then(function(result) {
			if (result.code !== 0) throw new Error(result.stderr || _('عملیات هسته اتر ناموفق بود.'));
			function refresh() {
				return fs.exec('/usr/libexec/gozarbin/aether-core.sh', ['status']).then(function(report) {
					var state = parse(report);
					if (state.state === 'done' || state.state === 'error') {
						poll.remove(refresh);
						notify(state.state === 'done' ? _('عملیات انجام شد.') : _('عملیات هسته اتر ناموفق بود.'), state.state === 'done' ? 'info' : 'error');
					}
				});
			}
			poll.add(refresh, 2);
			return refresh();
		}).catch(function(error) { notify(_('اجرا نشد: ') + error.message, 'error'); });
	},

	syncMainSwitch: function() {
		if (this.serviceBusy || this.serviceEnabled == null) return;
		this.syncingSwitch = true;
		try {
			var field = this.enabledOption && this.enabledOption.getUIElement('main');
			if (field && String(this.enabledOption.formvalue('main')) !== (this.serviceEnabled ? '1' : '0')) field.setValue(this.serviceEnabled ? '1' : '0');
			if (this.mainSwitchInput) {
				this.mainSwitchInput.checked = !!this.serviceEnabled;
				this.mainSwitchInput.setAttribute('aria-checked', String(!!this.serviceEnabled));
			}
		} finally { this.syncingSwitch = false; }
	},

	readServiceState: function() {
		var self = this;
		return fs.exec('/usr/libexec/gozarbin/traffic.sh').then(function(result) {
			var state = parse(result);
			if (result.code !== 0 || typeof state.running !== 'boolean' || typeof state.enabled !== 'boolean')
				throw new Error(result.stderr || _('وضعیت سرویس دریافت نشد.'));
			self.applyTraffic(state); return state;
		});
	},

	setServiceEnabled: function(requested) {
		var self = this;
		if (this.serviceBusy) return Promise.resolve();
		this.serviceBusy = true; this.updateServiceToggle();
		this.dismissedConflict = '';
		return this.readServiceState().then(function(state) {
			var enabled = requested == null ? !state.running : requested;
			self.mainSwitchIntent = null;
			self.blockedActivation = false;
			var check = enabled ? fs.exec('/usr/libexec/gozarbin/passwall2-detect.sh', ['--json']).then(function(result) {
				var proxies = parse(result);
				if (result.code !== 0 || typeof proxies.active !== 'boolean') throw new Error(result.stderr || _('وضعیت سرویس دریافت نشد.'));
				self.proxyState = proxies;
				if (proxies.active || proxies.zirgozar_active) { self.blockedActivation = true; self.showProxyConflict(); return false; }
				return true;
			}) : Promise.resolve(true);
			return check.then(function(allowed) {
				if (!allowed) return;
				return fs.exec('/usr/bin/gozarbinctl', [enabled ? 'on' : 'off']).then(function(result) {
					if (result.code !== 0) throw new Error(result.stderr || result.stdout || String(result.code));
					return self.readServiceState();
				});
			});
		}).catch(function(error) {
			if (/conflict:/.test(error.message)) {
				self.blockedActivation = true;
				return self.checkProxyConflict();
			}
			notify(_('اجرا نشد: ') + error.message, 'error');
		}).finally(function() {
			self.serviceBusy = false;
			self.updateServiceToggle(); self.syncMainSwitch(); self.showProxyConflict();
		});
	},

	renderActions: function() {
		var self = this;
		var run = function(command, args, success) {
			return fs.exec(command, args).then(function(result) {
				if (result.code === 0) notify(success);
				else notify(_('فرمان با خطا تمام شد: ') + (result.stderr || result.stdout || result.code), 'error');
			}).catch(function(error) {
				notify(_('اجرا نشد: ') + error.message, 'error');
			});
		};
		var actions = E('div', { 'class': 'ae-actions' }, [
			this.action(_('پاک‌کردن داده‌های سایفون'), 'neutral', function() { return self.runCoreAction('clear-psiphon'); }),
			/* The scan is not a thing a user starts; it is how Gozarbin connects.
			 * What they can ask for is that it stop reusing the server it found
			 * last time, which is what this does. */
			this.action(_('اسکن دوباره و اتصال'), 'neutral', function() {
				notify(_('سرور ذخیره‌شده پاک شد؛ اسکن تازه آغاز می‌شود و ممکن است چند دقیقه طول بکشد.'));
				return run('/usr/bin/gozarbinctl', [ 'rescan' ], _('اسکن تازه آغاز شد.'));
			}),
			/* Asked again at the moment of the click, not taken from the report
			 * this page loaded with: a router that was missing something a few
			 * minutes ago may not be now. And a package manager that reaches for
			 * the network to conclude there is nothing to do is a poor way to
			 * answer a question that is already answered locally. */
			this.action(_('نصب پیش‌نیازهای جا افتاده'), 'neutral', function() {
				return fs.exec('/usr/libexec/gozarbin/deps.sh', [ '--json' ]).then(function(result) {
					var state = parse(result);
					self.dependencyState = state;
					if (state.complete !== false) {
						notify(_('پیش‌نیازها از قبل دانلود و نصب شده‌اند؛ کاری لازم نیست.'));
						return;
					}
					notify(_('نصب این بسته‌ها آغاز شد: ') + (state.missing || '') +
						_(' — بسته به سرعت اینترنت روتر ممکن است طول بکشد.'));
					return run('/usr/bin/gozarbinctl', [ 'install-deps' ],
						_('پیش‌نیازها نصب شدند. صفحه را تازه کنید.')).then(function() {
							return fs.exec('/usr/libexec/gozarbin/deps.sh', ['--json']).then(function(report) { self.dependencyState = parse(report); });
						});
				}).catch(function(error) {
					notify(_('بررسی پیش‌نیازها ناموفق بود: ') + error.message, 'error');
				}).finally(function() {
					window.setTimeout(function() { self.dependenciesButton.disabled = self.dependencyState.complete === true; }, 0);
				});
			})
		]);
		this.dependenciesButton = actions.lastElementChild.querySelector('button');
		this.dependenciesButton.disabled = this.dependencyState.complete === true;
		return actions;
	},

	/* Two LuCI defaults quietly empty half of /etc/config/gozarbin on the first
	 * save: an option the current mode hides is deleted, and a flag or list
	 * whose value equals the widget default is deleted too. Hiding an option is
	 * not the user asking to forget it, and "the default" is still an answer, so
	 * both are turned off here. Text fields keep rmempty, because refusing to
	 * save a page over one blank box would be worse than either. */
	renderLogs: function() {
		var root = E('div', { 'class': 'ae-logs' });
		['runtime', 'core'].forEach(function(kind) {
			var content = E('pre', { 'class': 'ae-log-content', 'dir': 'ltr', 'tabindex': '0' }, _('در حال دریافت گزارش…'));
			var feedback = E('span', { 'class': 'ae-log-feedback', 'role': 'status' });
			var busy = false;
			function refresh(force) {
				if (busy || (!force && (!root.isConnected || !root.getClientRects().length))) return Promise.resolve();
				busy = true;
				return fs.exec('/usr/libexec/gozarbin/logs.sh', [kind]).then(function(result) {
					if (result.code !== 0) throw new Error(result.stderr || _('گزارش دریافت نشد.'));
					var atEnd = content.scrollTop + content.clientHeight >= content.scrollHeight - 10;
					content.textContent = result.stdout || _('هنوز گزارشی ثبت نشده است.');
					if (atEnd || !content.dataset.drawn) content.scrollTop = content.scrollHeight;
					content.dataset.drawn = '1'; feedback.textContent = '';
				}).catch(function(error) { feedback.textContent = _('اجرا نشد: ') + error.message; })
					.finally(function() { busy = false; });
			}
			function button(label, action) {
				var node = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-neutral', 'click': function() {
					node.disabled = true;
					Promise.resolve().then(action).catch(function(error) { feedback.textContent = _('اجرا نشد: ') + error.message; })
						.finally(function() { node.disabled = false; });
				} }, label);
				return node;
			}
			root.appendChild(E('section', { 'class': 'ae-log-panel' }, [
				E('h3', {}, [appearance.icon(kind === 'runtime' ? 'book' : 'server'), kind === 'runtime' ? _('گزارش اجرا') : _('گزارش هسته')]),
				E('p', { 'class': 'ae-help-text' }, _('گزارش گذربین هر ۵ ثانیه تازه می شود. پاک کردن فقط پیام های قبلی همین بخش را از نمایش کنار می گذارد و گزارش سیستم را حذف نمی کند.')),
				E('div', { 'class': 'ae-log-toolbar' }, [
					button(_('تازه سازی'), function() { return refresh(true); }),
					button(_('کپی'), function() {
						if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(content.textContent).then(function() { feedback.textContent = _('کپی شد.'); });
						var area = E('textarea', { 'class': 'ae-copy-buffer', 'readonly': true }, content.textContent);
						document.body.appendChild(area);
						try { area.select(); if (!document.execCommand('copy')) throw new Error(_('کپی انجام نشد.')); feedback.textContent = _('کپی شد.'); }
						finally { area.remove(); }
					}),
					button(_('پاک کردن'), function() {
						return fs.exec('/usr/libexec/gozarbin/logs.sh', ['clear-' + kind]).then(function(result) {
							if (result.code !== 0) throw new Error(result.stderr || _('پاک کردن گزارش ناموفق بود.'));
							return refresh(true);
						});
					}), feedback
				]), content
			]));
			poll.add(function() { return refresh(false); }, 5);
			window.setTimeout(function() { refresh(true); }, 0);
		});
		return root;
	},

	option: function(section, tab, type, name, title, description) {
		var help = {
			protocol: _('WireGuard از UDP و MASQUE از HTTP/2 یا HTTP/3 استفاده می کند. حالت های دو لایه، تونل داخلی را از تونل بیرونی عبور می دهند.'),
			masque_transport: _('h2 از TCP و h3 از QUIC روی UDP استفاده می کند. اگر UDP محدود است، h2 را انتخاب کنید.'),
			outer_peer: _('سرور لایه بیرونی به شکل IP:port. این سرور مسیر رسیدن به تونل داخلی است؛ خالی بگذارید تا هسته انتخاب کند.'),
			inner_peer: _('سرور لایه داخلی به شکل IP:port که از داخل تونل بیرونی به آن وصل می شوید. خالی یعنی انتخاب هسته.'),
			peer: _('سرور اتصال مستقیم اتر به شکل IP:port. با خالی گذاشتن، انتخاب سرور به هسته و اسکن سپرده می شود.'),
			tor: _('off: خاموش؛ only: فقط TOR؛ chain: TOR داخل WARP؛ reverse: WARP از راه TOR. حالت reverse به MASQUE نیاز دارد و TOR با سایفون همزمان قابل استفاده نیست.'),
			socks_port: _('پورت پراکسی SOCKS5 محلی و خروجی نهایی اتصال. برای تنظیم پراکسی در برنامه ها از این پورت و آدرس شنود استفاده کنید.'),
			geosite_url: _('نشانی فایل rule-set دامنه های ایرانی با قالب SRS سینگ باکس. این دامنه ها هنگام فعال بودن عبور مستقیم ایران از تونل عبور نمی کنند.'),
			block_ads: _('با استفاده از فهرست تبلیغات، اتصال به دامنه های تبلیغاتی و ردیاب مسدود می شود. این گزینه در حالت شفاف و TUN کاربرد دارد.'),
			geosite_ads_url: _('نشانی فایل rule-set تبلیغات و ردیاب ها با قالب SRS سینگ باکس. فهرست از برگه به روزرسانی دریافت می شود.'),
			ip_mode: _('نوع آدرس سرورهای مورد استفاده در اسکن و اتصال: IPv4، IPv6 یا هر دو. IPv6 به ارتباط IPv6 فعال روی روتر نیاز دارد.'),
			perf: _('low برای روترهای کم مصرف، medium برای منابع متوسط و high برای سرورها است. این انتخاب میزان استفاده هسته از منابع را تغییر می دهد.'),
			quick_reconnect: _('ابتدا آخرین سرور موفق بررسی می شود؛ اگر پاسخ ندهد، اسکن تازه آغاز می شود.'),
			log_level: _('error فقط خطاها، warn هشدارها، info مراحل اتصال، debug جزئیات عیب یابی و trace ریزترین پیام ها را ثبت می کند. برای استفاده عادی info مناسب است.'),
			singbox_log_level: _('سطح جزئیات گزارش سینگ باکس در حالت شفاف و TUN. debug برای عیب یابی است و پیام های بیشتری تولید می کند.'),
			tproxy_port: _('پورت داخلی سینگ باکس برای دریافت ترافیک هدایت شده توسط فایروال. نباید با پورت سایر سرویس ها یکسان باشد.'),
			route_table: _('شماره جدول مسیریابی اختصاصی گذربین در حالت شفاف. با جدول برنامه های دیگر یکسان نباشد.'),
			tun_name: _('نام رابط مجازی ساخته شده برای حالت TUN؛ با رابط موجود دیگری یکسان نباشد.'),
			tun_address: _('آدرس IPv4 و پیشوند شبکه رابط TUN به شکل CIDR؛ با شبکه داخلی روتر تداخل نداشته باشد.'),
			tun_address6: _('آدرس IPv6 و پیشوند شبکه رابط TUN به شکل CIDR؛ با شبکه های دیگر تداخل نداشته باشد.'),
			tun_mtu: _('بیشترین اندازه بسته رابط TUN بر حسب بایت. کاهش آن ممکن است مشکل بارگذاری بعضی سایت ها را رفع کند.'),
			tor_port: _('پورت داخلی پراکسی TOR روی روتر؛ با پورت SOCKS5 اصلی و سایر سرویس ها یکسان نباشد.'),
			psiphon_port: _('پورت داخلی پراکسی سایفون روی روتر؛ با پورت SOCKS5 اصلی و سایر سرویس ها یکسان نباشد.')
		};
		description = description || help[name];
		var option = section.taboption(tab, type, name, title, description);
		option.retain = true;
		if (type === form.Flag || type === form.ListValue)
			option.rmempty = false;
		return option;
	},

	renderForm: function(system, tunnel) {
		var map = new form.Map('gozarbin', _('تنظیمات پایه'),
			_('برای ثبت سایر تنظیمات، ذخیره و اعمال را بزنید.'));
		var section = map.section(form.NamedSection, 'main', 'gozarbin');
		section.addremove = false;

		section.tab('general', _('تنظیمات پایه'));
		section.tab('routing', _('مدیریت قوانین'));
		section.tab('advanced', _('شبکه'));
		section.tab('aether', _('تنظیمات دیگر'));
		section.tab('reports', _('گزارش'));

		var self = this;
		var option, enabled, mode, protocol, psiphon, scan, socks, http;

		enabled = self.option(section, 'general', form.Flag, 'enabled', _('کلید اصلی'),
			_('کلید اصلی برنامه را مستقیم روشن یا خاموش می کند؛ نیازی به ذخیره و اعمال نیست.') + ' ' +
			_('اگر هویت WARP موجود نباشد، هنگام اتصال خودکار ثبت و ذخیره می شود.'));
		this.enabledOption = enabled;
		enabled.cfgvalue = function(sectionId) { return self.serviceEnabled == null ? uci.get('gozarbin', sectionId, 'enabled') : self.serviceEnabled ? '1' : '0'; };
		enabled.onchange = function(event, sectionId, value) {
			var wanted = value === '1' || value === true;
			if (!self.syncingSwitch && wanted !== self.serviceEnabled) return self.setServiceEnabled(wanted);
		};

		mode = self.option(section, 'general', form.ListValue, 'mode', _('حالت کار'),
			_('TProxy: کل ترافیک شبکه از طریق nftables و sing-box. TUN: یک کارت شبکه مجازی به‌جای TProxy. SOCKS5: فقط پراکسی محلی، بدون دست‌کاری ترافیک شبکه.'));
		mode.value('tproxy', _('پراکسی شفاف شبکه (TProxy)'));
		mode.value('tun', _('کارت شبکهٔ مجازی (TUN)'));
		mode.value('socks', _('فقط پراکسی SOCKS5'));
		mode.default = 'tproxy';

		protocol = self.option(section, 'general', form.ListValue, 'protocol', _('پروتکل اتر'));
		protocol.value('wg', 'WireGuard');
		protocol.value('masque', 'MASQUE');
		protocol.value('gool', 'WARP in WARP (classic Gool)');
		protocol.value('mim', 'MASQUE in MASQUE');
		protocol.value('gool_masque', 'WireGuard over MASQUE (new Gool)');
		protocol.default = 'masque';

		/* Psiphon or Tor may dial the tunnel, never both; with Psiphon doing it,
		 * or standing in for WARP altogether, the Tor options have nothing to do. */
		option = self.option(section, 'general', form.ListValue, 'masque_transport', _('انتقال MASQUE'));
		option.value('h2', 'h2'); option.value('h3', 'h3'); option.default = 'h2';
		['masque', 'mim', 'gool_masque'].forEach(function(value) { option.depends('protocol', value); });

		['outer_peer', 'inner_peer', 'peer'].forEach(function(key) {
			var field = self.option(section, 'general', form.Value, key,
				key === 'outer_peer' ? _('آدرس لایه بیرونی') : key === 'inner_peer' ? _('آدرس لایه داخلی') : _('آدرس اتر'));
			field.datatype = 'ipaddrport(1)';
			field.placeholder = key === 'inner_peer' ? '162.159.193.10:2408' : '162.159.199.1:443';
			(key === 'peer' ? ['masque', 'wg'] : ['gool', 'mim', 'gool_masque']).forEach(function(value) { field.depends('protocol', value); });
		});

		option = self.option(section, 'general', form.ListValue, 'tor', _('حالت تور'));
		['off', 'only', 'chain', 'reverse'].forEach(function(value) { option.value(value, value); });
		option.default = 'off';
		option.cfgvalue = function(sectionId) {
			return uci.get('gozarbin', sectionId, 'tor') || (uci.get('gozarbin', sectionId, 'tor_reverse') === '1' ? 'reverse' : 'off');
		};
		option.validate = function(sectionId, value) {
			if (value !== 'off' && this.section.formvalue(sectionId, 'psiphon') !== 'off') return _('تور و سایفون را هم‌زمان انتخاب نکنید.');
			var chosen = this.section.formvalue(sectionId, 'protocol');
			return value === 'reverse' && (chosen === 'wg' || chosen === 'gool') ? _('اتصال معکوس تور به انتقال MASQUE نیاز دارد.') : true;
		};

		option = self.option(section, 'general', form.Flag, 'tor_scan_fallback', _('Tor خودکار پس از شکست اسکن'),
			_('اگر اسکن مستقیم سرور پیدا نکند، یک بار با Tor اسکن می‌شود. سرور یافت‌شده دوباره مستقیم آزمایش می‌شود؛ فقط اگر مستقیم کار نکند، اتصال با Tor ادامه می‌یابد.'));
		option.default = '0';
		option.depends({ protocol: 'masque', psiphon: 'off' });
		option.depends({ protocol: 'masque', psiphon: 'chain' });

		psiphon = self.option(section, 'general', form.ListValue, 'psiphon', _('حالت سایفون'),
			system.psiphon
				? _('«داخل WARP»: خروجی Psiphon در کشور انتخابی، و شبکه فقط WARP را می‌بیند. «WARP از راه Psiphon»: خروجی WARP است و شبکه هرگز WARP را نمی‌بیند؛ فقط با MASQUE. «فقط Psiphon»: بدون WARP. پورت SOCKS5 در هر حالت خروجی نهایی است.')
				: _('فایل Psiphon روی این روتر نیست؛ بستهٔ gozarbin را دوباره نصب کنید. تا آن موقع این گزینه نادیده گرفته می‌شود.'));
		psiphon.value('off', _('خاموش'));
		psiphon.value('chain', _('Psiphon داخل WARP (خروجی Psiphon)'));
		psiphon.value('reverse', _('WARP از راه Psiphon (خروجی WARP)'));
		psiphon.value('only', _('فقط Psiphon، بدون WARP'));
		psiphon.default = 'reverse';
		/* Psiphon carries TCP alone; WireGuard and WARP-in-WARP answer on UDP. */
		psiphon.validate = function(section_id, value) {
			if (value !== 'off' && this.section.formvalue(section_id, 'tor') !== 'off') return _('تور و سایفون را هم‌زمان انتخاب نکنید.');
			var chosen = this.section.formvalue(section_id, 'protocol');
			if (value === 'reverse' && (chosen === 'wg' || chosen === 'gool'))
				return _('WireGuard و WARP-in-WARP روی UDP کار می‌کنند و Psiphon فقط TCP می‌برد؛ برای این حالت پروتکل را MASQUE کنید.');
			return true;
		};

		option = self.option(section, 'general', form.ListValue, 'psiphon_region', _('کشور خروجی Psiphon'),
			_('Psiphon تلاش می‌کند از این کشور خارج شود. اگر الان در آن کشور سروری نداشته باشد، ممکن است اصلاً وصل نشود؛ بهتر است روی «خودکار» بماند.'));
		option.value('', _('خودکار'));
		/* The blank choice is "automatic", an answer rather than a gap. The
		 * rmempty = false the helper sets makes LuCI refuse a blank list value
		 * as "must not be empty"; optional lets it through, and saving it
		 * deletes the option, which the service and gozarbinctl both read as
		 * automatic. */
		option.optional = true;
		var offered = regionCodes(tunnel && tunnel.psiphon_regions);
		var codes = Object.keys(COUNTRIES);
		offered.forEach(function(code) { if (codes.indexOf(code) < 0) codes.push(code); });
		var saved = String(uci.get('gozarbin', 'main', 'psiphon_region') || '').toUpperCase();
		if (/^[A-Z]{2}$/.test(saved) && codes.indexOf(saved) < 0) codes.push(saved);
		codes.sort(function(a, b) {
			return String(COUNTRIES[a] || a).localeCompare(String(COUNTRIES[b] || b), 'fa');
		}).forEach(function(code) {
			option.value(code, countryName(code) + (offered.indexOf(code) >= 0 ? ' ✓' : ''));
		});
		if (offered.length)
			option.description += ' ' + _('کشورهایی که Psiphon همین حالا ارائه می‌کند با ✓ مشخص شده‌اند.');
		option.depends('psiphon', 'chain');
		option.depends('psiphon', 'reverse');
		option.depends('psiphon', 'only');

		option = self.option(section, 'general', form.ListValue, 'psiphon_mode', _('شیوهٔ اتصال Psiphon'),
			_('اگر Psiphon وصل نمی‌شود، CDN را امتحان کنید: فقط از راه CDN و پنهان پشت دامنه‌های دیگر وصل می‌شود.'));
		option.value('auto', _('خودکار'));
		option.value('cdn', _('فقط از راه CDN'));
		option.value('direct', _('مستقیم، بدون CDN'));
		option.default = 'auto';
		option.depends('psiphon', 'chain');
		option.depends('psiphon', 'reverse');
		option.depends('psiphon', 'only');

		scan = self.option(section, 'general', form.ListValue, 'scan', _('روش اسکن'),
			_('turbo سریع‌ترین و ironclad مطمئن‌ترین حالت است.'));
		['balanced', 'turbo', 'thorough', 'verified', 'stealth', 'ironclad'].forEach(function(value) { scan.value(value, value); });
		scan.default = 'balanced';

		socks = self.option(section, 'general', form.Value, 'socks_port', _('پورت SOCKS5'));
		socks.datatype = 'port';
		socks.placeholder = '1819';

		http = self.option(section, 'general', form.Value, 'http_port', _('پورت پراکسی HTTP'),
			_('صفر یعنی خاموش. برای برنامه‌هایی که فقط HTTP proxy می‌پذیرند مفید است.'));
		http.datatype = 'port';
		http.placeholder = '0';

		/* ---- routing ---- */

		/* One option, one source. The GeoIP ranges also go into nftables, so
		 * traffic to an Iranian address never reaches sing-box at all; GeoSite
		 * catches Iranian sites hosted abroad, by name. */
		option = self.option(section, 'routing', form.Flag, 'geo_enabled', _('عبور مستقیم ترافیک ایران'),
			_('سایت‌ها و سرویس‌های ایرانی — هم بر اساس IP و هم بر اساس نام دامنه — بدون تونل و مستقیم باز می‌شوند. فهرست‌ها در اولین اتصال خودکار دریافت می‌شوند.'));
		option.default = '1';
		option = self.option(section, 'routing', form.Flag, 'block_ads', _('مسدود کردن تبلیغات و ردیاب‌ها'));

		option = self.option(section, 'routing', form.Flag, 'dns', _('عبور DNS از تونل'),
			_('با این گزینه دامنه‌ها از داخل تونل پاسخ می‌گیرند و دامنه‌های ایرانی از DNS اینترنت خودتان. فقط در حالت شفاف.'));
		option.default = '1';

		/* Cloudflare places a WARP exit where the connection to it starts, so a
		 * second core dials WARP through Tor and these domains leave on a
		 * Cloudflare address outside Iran. */
		option = self.option(section, 'routing', form.Flag, 'unblock', _('خروجی غیرایرانی برای سرویس‌های تحریمی'),
			_('ترافیک دامنه‌های زیر از وارپی عبور می‌کند که از راه Tor وصل شده، پس این سرویس‌ها موقعیت را خارج از ایران می‌بینند. کندتر است، حدود ۳۰ مگابایت حافظه می‌گیرد و اتصال اول حدود دو دقیقه طول می‌کشد. فقط در حالت شفاف و TUN.'));
		option.default = '0';

		option = self.option(section, 'routing', form.DynamicList, 'unblock_domain', _('دامنه‌های خروجی غیرایرانی'),
			_('هر دامنه زیردامنه‌هایش را هم در بر می‌گیرد.'));
		option.datatype = 'hostname';
		option.depends('unblock', '1');

		option = self.option(section, 'routing', form.Value, 'geoip_url', _('منبع GeoIP'),
			_('نشانی فایل rule-set. می‌توانید نشانی آینه یا فایل دلخواه خود را بگذارید.'));
		option.default = GEO_DEFAULTS.geoip_url;
		option = self.option(section, 'routing', form.Value, 'geosite_url', _('منبع GeoSite'));
		option.default = GEO_DEFAULTS.geosite_url;

		option = self.option(section, 'routing', form.Value, 'geosite_ads_url', _('منبع فهرست تبلیغات'));
		option.default = GEO_DEFAULTS.geosite_ads_url;

		option = self.option(section, 'routing', form.Value, 'config_file', _('فایل پیکربندی گذربین'),
			_('مسیر فایل هویت و قواعد مسیریابی اختصاصی هستهٔ تونل.'));
		option.placeholder = '/etc/gozarbin/gozarbin.toml';

		/* ---- advanced ---- */

		option = self.option(section, 'advanced', form.ListValue, 'ip_mode', _('نسخهٔ IP'));
		option.value('v4', _('فقط IPv4'));
		option.value('v6', _('فقط IPv6'));
		option.value('both', _('هر دو'));

		option = self.option(section, 'advanced', form.ListValue, 'noize', _('پروفایل استتار'),
			_('اگر پروفایل پیش‌فرض از فیلترینگ رد نشد، gfw را امتحان کنید.'));
		[ 'off', 'light', 'firewall', 'balanced', 'gfw', 'aggressive' ].forEach(function(value) {
			option.value(value);
		});

		option = self.option(section, 'advanced', form.ListValue, 'perf', _('پروفایل مصرف منابع'));
		option.value('low', _('کم — روترها و بردهای کوچک'));
		option.value('medium', _('متوسط'));
		option.value('high', _('زیاد — سرور'));

		option = self.option(section, 'advanced', form.Flag, 'tls_verify', _('بررسی گواهی TLS'),
			_('گواهی سرورهایی را که هسته با آن‌ها TLS برقرار می‌کند (API وارپ، DoH و لبهٔ MASQUE) بررسی می‌کند تا کسی وسط راه نتواند خودش را جای آن‌ها جا بزند. پیش‌فرض خاموش است؛ اگر شبکه TLS را رهگیری کند، با روشن بودنش تونل وصل نمی‌شود.'));
		option.default = '0';

		option = self.option(section, 'advanced', form.Flag, 'quick_reconnect', _('اتصال سریع با آخرین سرور موفق'));
		option = self.option(section, 'advanced', form.Flag, 'accounting', _('شمارش مصرف آپلود و دانلود'),
			_('شمارنده‌های nftables روی مسیر پراکسی. خاموش کردن آن نمایش مصرف را غیرفعال می‌کند.'));
		option.default = '1';

		option = self.option(section, 'reports', form.ListValue, 'log_level', _('سطح گزارش گذربین'));
		[ 'error', 'warn', 'info', 'debug', 'trace' ].forEach(function(value) { option.value(value); });
		option = self.option(section, 'reports', form.ListValue, 'singbox_log_level', _('سطح گزارش sing-box'));
		[ 'error', 'warn', 'info', 'debug' ].forEach(function(value) { option.value(value); });

		option = self.option(section, 'advanced', form.DynamicList, 'lan_interface', _('رابط‌های شبکهٔ داخلی'),
			_('ترافیک این رابط‌ها به تونل هدایت می‌شود.'));
		option.placeholder = 'br-lan';
		option.depends({ mode: 'tproxy' });

		option = self.option(section, 'advanced', form.Value, 'tproxy_port', _('پورت TProxy'));
		option.datatype = 'port';
		option.depends({ mode: 'tproxy' });
		option = self.option(section, 'advanced', form.Value, 'mark', _('علامت فایروال (fwmark)'),
			_('بایت آخر باید ff بماند. Passwall2 و Passwall و ShadowSocksR علامتی که به ff ختم شود را رد می‌کنند؛ در غیر این صورت ترافیک خود گذربین را هم به پراکسی خودشان می‌برند و تونل وصل می‌شود ولی چیزی از آن رد نمی‌شود.'));
		option.depends({ mode: 'tproxy' });
		option = self.option(section, 'advanced', form.Value, 'route_table', _('شمارهٔ جدول مسیریابی'));
		option.datatype = 'uinteger';
		option.depends({ mode: 'tproxy' });

		option = self.option(section, 'advanced', form.Value, 'tun_name', _('نام کارت شبکهٔ مجازی'));
		option.depends({ mode: 'tun' });
		option = self.option(section, 'advanced', form.Value, 'tun_address', _('نشانی IPv4 کارت مجازی'));
		option.datatype = 'cidr4';
		option.depends({ mode: 'tun' });
		option = self.option(section, 'advanced', form.Value, 'tun_address6', _('نشانی IPv6 کارت مجازی'));
		option.datatype = 'cidr6';
		option.depends({ mode: 'tun' });
		option = self.option(section, 'advanced', form.Value, 'tun_mtu', _('MTU کارت مجازی'));
		option.datatype = 'range(576,65535)';
		option.depends({ mode: 'tun' });

		option = self.option(section, 'advanced', form.Value, 'psiphon_port', _('پورت داخلی Psiphon'),
			_('فقط روی 127.0.0.1. در حالت «Psiphon داخل WARP» تونل WARP این‌جا گوش می‌دهد و Psiphon روی پورت SOCKS5؛ در حالت «WARP از راه Psiphon» خود Psiphon. نباید با پورت‌های دیگر یکی باشد.'));
		option.datatype = 'port';
		option.placeholder = '1825';
		option.depends('psiphon', 'chain');
		option.depends('psiphon', 'reverse');

		option = self.option(section, 'advanced', form.Value, 'socks_address', _('نشانی شنود پراکسی'),
			_('پیش‌فرض 127.0.0.1 است و برای کار عادی درست است: حالت شفاف از همین استفاده می‌کند. فقط اگر می‌خواهید دستگاه‌های شبکه مستقیماً به SOCKS5 وصل شوند 0.0.0.0 بگذارید — آن‌وقت پراکسی بدون رمز عبور برای کل شبکه باز می‌شود.'));
		option.placeholder = '127.0.0.1';

		(this.coreOptions && this.coreOptions.options || []).forEach(function(spec) {
			var reportOption = /^(AETHER_TOR_LOG|AETHER_STATS(_SECS)?|AETHER_EXIT_LOC(_SECS)?)$/.test(spec.env);
			var field = self.option(section, reportOption ? 'reports' : 'aether', spec.type === 'boolean' || spec.type === 'choice' ? form.ListValue : form.Value,
				spec.key, i18n.clean(spec.label[i18n.get()] || spec.label.en));
			var hint = spec.default_hint && (spec.default_hint[i18n.get()] || spec.default_hint.en) || _('خودکار');
			field.description = i18n.clean(spec.help && (spec.help[i18n.get()] || spec.help.en) || '') + ' ' + _('پیش فرض: ') + i18n.clean(hint);
			field.placeholder = spec.default_value || i18n.clean(hint);
			field.rmempty = true; field.optional = true;
			if (spec.type === 'boolean' || spec.type === 'choice') {
				field.value('', _('پیش‌فرض هسته') + ' (' + i18n.clean(hint) + ')');
				if (spec.type === 'boolean') { field.value('1', _('روشن')); field.value('0', _('خاموش')); }
				else spec.choices.forEach(function(value) { field.value(value, value); });
			}
			if (spec.type === 'number') field.datatype = spec.env === 'AETHER_TLS_SERVER_PADDING' ? 'range(0,65535)' : 'uinteger';
			if (spec.secret) field.password = true;
		});
		['tor_port', 'psiphon_port'].forEach(function(key) {
			var field = self.option(section, 'aether', form.Value, key, key === 'tor_port' ? _('پورت داخلی تور') : _('پورت داخلی سایفون'));
			field.datatype = 'port'; field.placeholder = key === 'tor_port' ? '1826' : '1825';
		});
		option = self.option(section, 'aether', form.Value, 'enroll_address', _('آدرس API ثبت WARP'),
			_('آدرس IP یا دامنه با پورت اختیاری؛ خالی یعنی انتخاب خودکار آدرس سرویس ثبت WARP.'));
		option.placeholder = '162.159.137.105:443';
		option = section.taboption('reports', form.DummyValue, '_logs', _('نمایش گزارش'));
		option.renderWidget = function() { return self.renderLogs(); };
		return map.render();
	},

	render: function(results) {
		var self = this;
		var passwall = parse(results[0]);
		var system = parse(results[1]);
		var deps = parse(results[2]);
		var traffic = parse(results[3]);
		this.connectivity = parse(results[8]);
		this.serviceEnabled = traffic.enabled === true;
		var core = parse(results[4]);
		var tunnel = parse(results[5]);
		try { this.coreOptions = JSON.parse(results[7] || '{}'); } catch (e) { this.coreOptions = {}; }

		/* The class is enough to reach the notifications and set the type.
		 * A dir on <body> would also flip LuCI's own navbar dropdowns, which
		 * are positioned in pixels and end up ten thousand of them off-screen. */
		document.body.classList.add('gozarbin-page');

		var version = system.gozarbin_version ? ' — ' + system.gozarbin_version.replace(/-r/, 'r') : '';
		return this.renderForm(system, tunnel).then(function(rendered) {
			var root = E('div', { 'class': 'gozarbin-rtl', 'dir': i18n.dir(), 'lang': i18n.get() }, [
				E('link', {
					'rel': 'stylesheet',
					/* The package build rewrites this path to the file name
					 * carrying the release. LuCI versions its own resource URLs
					 * but not one a view asks for itself, and a query string is
					 * no help either: it only moves when the version does, while
					 * the file it points at can change under it. */
					'href': L.resource('view/gozarbin/gozarbin.css')
				}),
				E('div', { 'class': 'ae-hero' }, [
					E('div', { 'class': 'ae-brand' }, [E('h2', {}, [appearance.logo(), _('گذربین'),
						E('bdi', { 'class': 'ae-version ae-num' }, version.replace(' — ', '') || 'Gozarbin')]),
						E('p', {}, _('دوست روزهای سخت اینترنتی در روتر شما'))]),
					appearance.controls()
				]),
				appearance.nav('settings'),
				self.renderDashboard(system, passwall, deps, traffic, tunnel),
				self.renderMarkNotice(passwall),
				self.renderCoreNotice(system, core),
				self.renderActions(),
				rendered, appearance.footer()
			]);
			appearance.bindNavigation(root);
			self.mainSwitchInput = appearance.mainSwitch(root);
			appearance.help(root);
			return root;
		});
	}
});
