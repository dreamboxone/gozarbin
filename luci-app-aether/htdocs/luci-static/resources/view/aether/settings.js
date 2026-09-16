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

var GEO_DEFAULTS = {
	geoip_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geoip-ir.srs',
	geosite_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs',
	geosite_ads_url: 'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-category-ads-all.srs'
};

/* Written by the init script into /var/run/aether/transparent-off. */
var REASONS = {
	passwall2: _('حالت شفاف اجرا نشده چون Passwall2 فعال است'),
	dependencies: _('حالت شفاف اجرا نشده چون یک پیش‌نیاز نصب نیست'),
	singbox: _('حالت شفاف اجرا نشده چون هستهٔ sing-box نصب نیست')
};

var MEGABYTE = 1024 * 1024;

function ltr(text) {
	return E('span', { 'class': 'ae-num' }, String(text));
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
	if (d > 0) return d + ' روز و ' + h + ' ساعت';
	if (h > 0) return h + ' ساعت و ' + m + ' دقیقه';
	if (m > 0) return m + ' دقیقه و ' + (s % 60) + ' ثانیه';
	return s + ' ثانیه';
}

function parse(result, fallback) {
	try { return JSON.parse((result && result.stdout) || '{}'); }
	catch (e) { return fallback || {}; }
}

/* LuCI writes its notifications in the page's own direction and labels the
 * dismiss button in English when no translation is installed. Both are fixed
 * here so a Persian message reads as one. */
function notify(message, kind) {
	/* LuCI appends the class verbatim, so an absent one lands as "undefined". */
	var node = ui.addNotification(null, E('p', {}, message), kind || 'info');
	try {
		if (!node || !node.querySelectorAll) {
			var all = document.querySelectorAll('.alert-message');
			node = all.length ? all[all.length - 1] : null;
		}
		if (!node) return null;
		node.setAttribute('dir', 'rtl');
		node.querySelectorAll('button, .btn').forEach(function(button) {
			button.textContent = _('بستن');
		});
	} catch (e) {}
	return node;
}

function card(label, klass) {
	var value = E('div', { 'class': 'ae-card-value' }, '—');
	var note = E('div', { 'class': 'ae-card-note' }, '');
	var bar = E('div', { 'class': 'ae-bar' }, E('span', {}));
	var node = E('div', { 'class': 'ae-card ' + (klass || '') }, [
		E('div', { 'class': 'ae-card-label' }, label), value, note
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
			fs.exec('/usr/libexec/aether/passwall2-detect.sh', [ '--json' ]).catch(soft),
			fs.exec('/usr/libexec/aether/system-info.sh').catch(soft),
			fs.exec('/usr/libexec/aether/deps.sh', [ '--json' ]).catch(soft),
			fs.exec('/usr/libexec/aether/traffic.sh').catch(soft),
			fs.exec('/usr/libexec/aether/singbox.sh', [ '--state' ]).catch(soft),
			uci.load('aether')
		]);
	},

	renderDashboard: function(system, passwall, deps, traffic) {
		var self = this;
		var service = card(_('وضعیت سرویس'));
		var usage = card(_('مصرف کل'));
		var up = card(_('ارسال (آپلود)'), 'ae-card-up');
		var down = card(_('دریافت (دانلود)'), 'ae-card-down');
		var build = card(_('نوع دستگاه'));
		var health = card(_('پیش‌نیازها و Passwall2'));

		build.value.textContent = '';
		build.value.appendChild(E('span', {}, system.model || _('نامشخص')));
		build.note.appendChild(ltr([
			system.release || '', system.arch || ''
		].filter(Boolean).join(' • ')));

		var kernelOk = system.tproxy && system.socket && system.nftables;
		health.value.textContent = '';
		var origins = {
			own: _('هستهٔ اختصاصی Aether'),
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
			passwall.active ? _('Passwall2 فعال') :
				(passwall.installed ? _('Passwall2 نصب، غیرفعال') : _('Passwall2 نصب نیست')),
			passwall.active ? 'warn' : 'ok'));
		if (deps && deps.complete === false && deps.missing)
			health.note.textContent = _('نصب نشده: ') + deps.missing;
		else
			health.note.textContent = _('همهٔ بسته‌های لازم نصب هستند.');

		var dash = E('div', { 'class': 'ae-dash' }, [
			service.node, up.node, down.node, usage.node, build.node, health.node
		]);

		this.state = { time: 0, upload: 0, download: 0, peak: 1 };
		this.cards = { service: service, usage: usage, up: up, down: down };
		this.applyTraffic(traffic);
		poll.add(function() {
			return fs.exec('/usr/libexec/aether/traffic.sh')
				.then(function(result) { self.applyTraffic(parse(result)); })
				.catch(function() {});
		}, 3);
		return dash;
	},

	applyTraffic: function(traffic) {
		if (!this.cards || !traffic) return;
		var cards = this.cards, previous = this.state;
		var running = traffic.running === true;
		var modes = { tproxy: _('پراکسی شفاف (TProxy)'), tun: _('حالت TUN'), socks: _('فقط SOCKS5') };

		cards.service.value.textContent = '';
		cards.service.value.appendChild(E('span', {
			'class': 'ae-dot ' + (running ? 'ae-dot-on' : (traffic.enabled ? 'ae-dot-warn' : ''))
		}));
		cards.service.value.appendChild(document.createTextNode(
			running ? _('در حال اجرا') : (traffic.enabled ? _('روشن، بالا نیامده') : _('خاموش'))));
		var note = [ modes[traffic.mode] || traffic.mode ];
		if (running) note.push(_('مدت اجرا: ') + duration(traffic.uptime));
		/* The reason comes from the init script, the only side that knows it.
		 * Guessing at it here produced a card that contradicted the dependency
		 * card beside it. */
		if (running && REASONS[traffic.transparent_off])
			note.push(REASONS[traffic.transparent_off]);
		cards.service.note.textContent = note.join(' • ');

		var upload = Number(traffic.upload) || 0, download = Number(traffic.download) || 0;
		var now = Number(traffic.time) || Math.floor(Date.now() / 1000);
		var span = previous.time ? now - previous.time : 0;
		/* The counters restart whenever the firewall rules are rebuilt; a drop
		 * means a reset, not negative throughput. */
		var upRate = span > 0 && upload >= previous.upload ? (upload - previous.upload) / span : 0;
		var downRate = span > 0 && download >= previous.download ? (download - previous.download) / span : 0;
		var peak = Math.max(previous.peak || 1, upRate, downRate, 1);

		if (traffic.accounting === false) {
			cards.up.value.textContent = _('غیرفعال');
			cards.down.value.textContent = _('غیرفعال');
			cards.usage.value.textContent = _('شمارش خاموش است');
			cards.usage.note.textContent = _('در برگهٔ پیشرفته روشن کنید.');
			return;
		}

		cards.up.value.textContent = '';
		cards.up.value.appendChild(rate(upRate));
		cards.up.note.textContent = '';
		cards.up.note.appendChild(E('span', {}, [ _('مجموع: '), amount(upload) ]));
		cards.up.bar.style.width = Math.round(upRate / peak * 100) + '%';

		cards.down.value.textContent = '';
		cards.down.value.appendChild(rate(downRate));
		cards.down.note.textContent = '';
		cards.down.note.appendChild(E('span', {}, [ _('مجموع: '), amount(download) ]));
		cards.down.bar.style.width = Math.round(downRate / peak * 100) + '%';

		cards.usage.value.textContent = '';
		cards.usage.value.appendChild(amount(upload + download));
		cards.usage.note.textContent = '';
		cards.usage.note.appendChild(count(
			(Number(traffic.upload_packets) || 0) + (Number(traffic.download_packets) || 0)));

		this.state = { time: now, upload: upload, download: download, peak: peak };
	},

	/* Silent unless there is something to act on. A router that is offline, or
	 * behind a blocked GitHub, or simply has not passed enough traffic for the
	 * check to have run, has nothing to be told about. */
	renderCoreNotice: function(system, core) {
		/* No version argument: the ACL matches on the whole command line, and the
		 * script looks up the current stable itself anyway. */
		var install = function() {
			notify(_('دریافت هستهٔ sing-box آغاز شد؛ بسته به سرعت اینترنت روتر ممکن است چند دقیقه طول بکشد.'));
			return fs.exec('/usr/bin/aetherctl', [ 'install-singbox' ])
				.then(function(result) {
					if (result.code === 0)
						notify(_('هستهٔ sing-box نصب شد. صفحه را تازه کنید.'));
					else
						notify(_('نصب هسته ناموفق بود: ') + (result.stderr || result.stdout || result.code), 'error');
				})
				.catch(function(error) { notify(_('اجرا نشد: ') + error.message, 'error'); });
		};

		if (!system.singbox) {
			var why = system.singbox_origin === 'passwall'
				? _('روی این روتر فقط هستهٔ متعلق به Passwall2 نصب است. Aether از آن استفاده نمی‌کند تا Passwall2 دست‌نخورده بماند و هستهٔ خودش را لازم دارد.')
				: _('حالت شفاف و حالت TUN به هستهٔ sing-box نیاز دارند.');
			return E('div', { 'class': 'ae-notice ae-notice-bad' }, [
				E('div', { 'class': 'ae-notice-text' }, [
					E('strong', {}, _('هستهٔ sing-box برای Aether نصب نیست')),
					E('div', {}, why)
				]),
				this.action(_('نصب هسته'), 'apply', install)
			]);
		}

		if (core && core.update === true && core.latest) {
			return E('div', { 'class': 'ae-notice ae-notice-warn' }, [
				E('div', { 'class': 'ae-notice-text' }, [
					E('strong', {}, _('نسخهٔ پایدار تازه‌ای از هستهٔ sing-box منتشر شده است')),
					E('div', {}, [
						_('نصب‌شده: '), ltr(core.installed || '—'),
						' — ', _('جدید: '), ltr(core.latest)
					])
				]),
				this.action(_('به‌روزرسانی'), 'apply', install)
			]);
		}

		return E([]);
	},

	action: function(label, style, handler) {
		return E('button', {
			'class': 'cbi-button cbi-button-' + style,
			'click': ui.createHandlerFn(this, handler)
		}, label);
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
		return E('div', { 'class': 'ae-actions' }, [
			this.action(_('راه‌اندازی مجدد سرویس'), 'apply', function() {
				return run('/etc/init.d/aether', [ 'restart' ], _('سرویس دوباره راه‌اندازی شد.'));
			}),
			this.action(_('توقف سرویس'), 'reset', function() {
				return run('/etc/init.d/aether', [ 'stop' ], _('سرویس متوقف شد.'));
			}),
			this.action(_('به‌روزرسانی فهرست IP ایران'), 'neutral', function() {
				return run('/usr/bin/aetherctl', [ 'update-iran' ], _('فهرست IP ایران به‌روزرسانی شد.'));
			}),
			this.action(_('به‌روزرسانی GeoIP و GeoSite'), 'neutral', function() {
				return run('/usr/bin/aetherctl', [ 'update-geo' ], _('منابع GeoIP و GeoSite به‌روزرسانی شدند.'));
			}),
			this.action(_('نصب پیش‌نیازهای جا افتاده'), 'neutral', function() {
				notify(_('نصب پیش‌نیازها آغاز شد؛ بسته به سرعت اینترنت روتر ممکن است طول بکشد.'));
				return run('/usr/bin/aetherctl', [ 'install-deps' ], _('پیش‌نیازها نصب شدند. صفحه را تازه کنید.'));
			})
		]);
	},

	/* Two LuCI defaults quietly empty half of /etc/config/aether on the first
	 * save: an option the current mode hides is deleted, and a flag or list
	 * whose value equals the widget default is deleted too. Hiding an option is
	 * not the user asking to forget it, and "the default" is still an answer, so
	 * both are turned off here. Text fields keep rmempty, because refusing to
	 * save a page over one blank box would be worse than either. */
	option: function(section, tab, type, name, title, description) {
		var option = section.taboption(tab, type, name, title, description);
		option.retain = true;
		if (type === form.Flag || type === form.ListValue)
			option.rmempty = false;
		return option;
	},

	renderForm: function(system) {
		var map = new form.Map('aether', _('تنظیمات Aether'),
			_('پراکسی و تفکیک ترافیک ایران روی روتر. پس از هر تغییر، «ذخیره و اعمال» را بزنید.'));
		var section = map.section(form.NamedSection, 'main', 'aether');
		section.addremove = false;

		section.tab('general', _('عمومی'));
		section.tab('routing', _('مسیریابی و تفکیک ترافیک'));
		section.tab('advanced', _('پیشرفته'));

		var self = this;
		var option, enabled, mode, transparent, force, protocol, scan, socks, http;

		enabled = self.option(section, 'general', form.Flag, 'enabled', _('فعال بودن سرویس'));

		mode = self.option(section, 'general', form.ListValue, 'mode', _('حالت کار'),
			_('TProxy: کل ترافیک شبکه از طریق nftables و sing-box. TUN: یک کارت شبکه مجازی به‌جای TProxy. SOCKS5: فقط پراکسی محلی، بدون دست‌کاری ترافیک شبکه.'));
		mode.value('tproxy', _('پراکسی شفاف شبکه (TProxy)'));
		mode.value('tun', _('کارت شبکهٔ مجازی (TUN)'));
		mode.value('socks', _('فقط پراکسی SOCKS5'));
		mode.default = 'tproxy';

		transparent = self.option(section, 'general', form.Flag, 'transparent', _('عبور دادن ترافیک شبکه از تونل'));
		transparent.depends({ mode: 'tproxy' });
		transparent.depends({ mode: 'tun' });
		transparent.default = '1';

		force = self.option(section, 'general', form.Flag, 'force_with_passwall2', _('اجرا هم‌زمان با Passwall2'),
			_('به‌طور پیش‌فرض اگر Passwall2 روشن باشد، حالت شفاف Aether اجرا نمی‌شود تا دو برنامه با هم تداخل نکنند.'));
		force.depends('transparent', '1');

		protocol = self.option(section, 'general', form.ListValue, 'protocol', _('پروتکل تونل'));
		protocol.value('masque', 'MASQUE (HTTP/3)');
		protocol.value('wg', 'WireGuard');
		protocol.value('gool', 'WARP-in-WARP (gool)');
		protocol.value('mim', 'MASQUE-in-MASQUE');

		scan = self.option(section, 'general', form.ListValue, 'scan', _('حالت اسکن سرور'),
			_('turbo سریع‌ترین و ironclad مطمئن‌ترین حالت است.'));
		scan.value('turbo', _('turbo — اولین سرور پاسخ‌گو'));
		scan.value('balanced', _('balanced — پیش‌فرض، سریع‌ترین از چند سرور'));
		scan.value('thorough', _('thorough — جست‌وجوی کامل محدوده‌ها'));
		scan.value('stealth', _('stealth — کم‌سروصدا برای شبکه‌های حساس'));
		scan.value('ironclad', _('ironclad — آزمایش واقعی هر سرور'));

		socks = self.option(section, 'general', form.Value, 'socks_port', _('پورت SOCKS5'));
		socks.datatype = 'port';
		socks.placeholder = '1819';

		http = self.option(section, 'general', form.Value, 'http_port', _('پورت پراکسی HTTP'),
			_('صفر یعنی خاموش. برای برنامه‌هایی که فقط HTTP proxy می‌پذیرند مفید است.'));
		http.datatype = 'port';
		http.placeholder = '0';

		/* ---- routing ---- */

		option = self.option(section, 'routing', form.Flag, 'iran_bypass', _('عبور مستقیم ترافیک ایران'),
			_('محدوده‌های IP ایران از تونل رد نمی‌شوند. پس از نصب، یک بار فهرست را به‌روزرسانی کنید.'));
		option.default = '1';

		option = self.option(section, 'routing', form.Value, 'iran4_url', _('منبع فهرست IPv4 ایران'));
		option = self.option(section, 'routing', form.Value, 'iran6_url', _('منبع فهرست IPv6 ایران'));

		option = self.option(section, 'routing', form.Flag, 'geo_enabled', _('استفاده از GeoIP و GeoSite'),
			_('قواعد sing-box (فایل‌های srs) برای تشخیص مقصدهای ایرانی بر اساس نام دامنه و IP.'));

		option = self.option(section, 'routing', form.ListValue, 'geo_action', _('رفتار با مقصدهای شناسایی‌شده'));
		option.value('direct', _('عبور مستقیم، بدون تونل'));
		option.value('aether', _('عبور از تونل'));
		option.value('block', _('مسدود کردن'));
		option.depends('geo_enabled', '1');

		option = self.option(section, 'routing', form.Value, 'geoip_url', _('منبع GeoIP'),
			_('نشانی فایل rule-set. می‌توانید نشانی آینه یا فایل دلخواه خود را بگذارید.'));
		option.default = GEO_DEFAULTS.geoip_url;
		option = self.option(section, 'routing', form.Value, 'geosite_url', _('منبع GeoSite'));
		option.default = GEO_DEFAULTS.geosite_url;

		option = self.option(section, 'routing', form.Flag, 'block_ads', _('مسدود کردن تبلیغات و ردیاب‌ها'));
		option = self.option(section, 'routing', form.Value, 'geosite_ads_url', _('منبع فهرست تبلیغات'));
		option.default = GEO_DEFAULTS.geosite_ads_url;

		option = self.option(section, 'routing', form.Value, 'config_file', _('فایل پیکربندی Aether'),
			_('مسیر فایل هویت و قواعد مسیریابی اختصاصی Aether.'));
		option.placeholder = '/etc/aether/aether.toml';

		/* ---- advanced ---- */

		option = self.option(section, 'advanced', form.ListValue, 'ip_mode', _('نسخهٔ IP'));
		option.value('v4', _('فقط IPv4'));
		option.value('v6', _('فقط IPv6'));
		option.value('both', _('هر دو'));

		option = self.option(section, 'advanced', form.ListValue, 'noize', _('پروفایل مبهم‌سازی'),
			_('اگر پروفایل پیش‌فرض از فیلترینگ رد نشد، gfw را امتحان کنید.'));
		[ 'off', 'light', 'firewall', 'balanced', 'gfw', 'aggressive' ].forEach(function(value) {
			option.value(value);
		});

		option = self.option(section, 'advanced', form.ListValue, 'perf', _('پروفایل مصرف منابع'));
		option.value('low', _('کم — روترها و بردهای کوچک'));
		option.value('medium', _('متوسط'));
		option.value('high', _('زیاد — سرور'));

		option = self.option(section, 'advanced', form.Flag, 'quick_reconnect', _('اتصال سریع با آخرین سرور موفق'));
		option = self.option(section, 'advanced', form.Flag, 'accounting', _('شمارش مصرف آپلود و دانلود'),
			_('شمارنده‌های nftables روی مسیر پراکسی. خاموش کردن آن نمایش مصرف را غیرفعال می‌کند.'));
		option.default = '1';

		option = self.option(section, 'advanced', form.ListValue, 'log_level', _('سطح گزارش Aether'));
		[ 'error', 'warn', 'info', 'debug', 'trace' ].forEach(function(value) { option.value(value); });
		option = self.option(section, 'advanced', form.ListValue, 'singbox_log_level', _('سطح گزارش sing-box'));
		[ 'error', 'warn', 'info', 'debug' ].forEach(function(value) { option.value(value); });

		option = self.option(section, 'advanced', form.DynamicList, 'lan_interface', _('رابط‌های شبکهٔ داخلی'),
			_('ترافیک این رابط‌ها به تونل هدایت می‌شود.'));
		option.placeholder = 'br-lan';
		option.depends({ mode: 'tproxy' });

		option = self.option(section, 'advanced', form.Value, 'tproxy_port', _('پورت TProxy'));
		option.datatype = 'port';
		option.depends({ mode: 'tproxy' });
		option = self.option(section, 'advanced', form.Value, 'mark', _('علامت فایروال (fwmark)'));
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

		option = self.option(section, 'advanced', form.Value, 'socks_address', _('نشانی شنود پراکسی'),
			_('پیش‌فرض 127.0.0.1 است و برای کار عادی درست است: حالت شفاف از همین استفاده می‌کند. فقط اگر می‌خواهید دستگاه‌های شبکه مستقیماً به SOCKS5 وصل شوند 0.0.0.0 بگذارید — آن‌وقت پراکسی بدون رمز عبور برای کل شبکه باز می‌شود.'));
		option.placeholder = '127.0.0.1';

		return map.render();
	},

	render: function(results) {
		var self = this;
		var passwall = parse(results[0]);
		var system = parse(results[1]);
		var deps = parse(results[2]);
		var traffic = parse(results[3]);
		var core = parse(results[4]);

		/* The class is enough to reach the notifications and set the type.
		 * A dir on <body> would also flip LuCI's own navbar dropdowns, which
		 * are positioned in pixels and end up ten thousand of them off-screen. */
		document.body.classList.add('aether-page');

		var version = system.aether_version ? ' — ' + system.aether_version : '';
		return this.renderForm(system).then(function(rendered) {
			return E('div', { 'class': 'aether-rtl', 'dir': 'rtl' }, [
				E('link', {
					'rel': 'stylesheet',
					/* LuCI versions its own resource URLs but not one a view asks
					 * for itself, so without this a browser keeps serving the
					 * stylesheet it cached before the package was upgraded. */
					'href': L.resource('view/aether/aether.css') + '?v=' +
						encodeURIComponent(system.aether_version || '0')
				}),
				E('h2', {}, 'Aether' + version),
				self.renderDashboard(system, passwall, deps, traffic),
				self.renderCoreNotice(system, core),
				self.renderActions(),
				rendered
			]);
		});
	}
});
