# تطبیق هسته اتر با گذربین

مرجع: Aether 2.4.0، کامیت بالادست `d58f9d5`. تمام ۱۱۹ متغیر عمومی معرفی شده در راهنمای هسته، در جدول زیر به کنترل یا عملیات مشخص متصل هستند. نام های قدیمی CLI که فقط میانبرند، کنترل تکراری ندارند.

هسته اتر و ابزارهای آن فقط زیر `/usr/libexec/gozarbin/cores/aether/` و سینگ باکس فقط زیر `/usr/libexec/gozarbin/cores/singbox/` قرار می گیرند. هیچ هسته ای از برنامه های دیگر استفاده یا تغییر نمی کند.

نسخه بسته گذربین از نسخه هسته مستقل است. بخش به روز رسانی سه ردیف مستقل برای برنامه، اتر و سینگ باکس دارد. دانلود هسته ها با SHA-256 رسمی و اجرای نسخه باینری بررسی می شود؛ فعال سازی با جابجایی پیوند نسخه و حفظ نسخه قبلی انجام می شود.

FinalMask و dialMode قابلیت هسته اتر نیستند؛ زیرگذر آن ها را با مسیر خروجی Xray ترکیب می کند. اسکن اتر، حالت های balanced، turbo، thorough، verified و ironclad را دارد؛ stealth نام سازگار قدیمی verified است.

| متغیر هسته | کنترل در گذربین |
| --- | --- |
| `AETHER_SOCKS` | `socks_address + socks_port` |
| `AETHER_HTTP_PROXY` | `http_port` |
| `AETHER_MARK` | `mark` |
| `AETHER_TOR` | `tor` |
| `AETHER_TOR_BIND` | `tor_port` |
| `AETHER_PSIPHON` | `psiphon` |
| `AETHER_PSIPHON_MODE` | `psiphon_mode` |
| `AETHER_PSIPHON_BIND` | `psiphon_port` |
| `AETHER_PSIPHON_REGION` | `psiphon_region` |
| `AETHER_QUICK_RECONNECT` | `quick_reconnect` |
| `AETHER_IP` | `ip_mode` |
| `AETHER_PEER` | `peer` |
| `AETHER_PROTOCOL` | `protocol` |
| `AETHER_GOOL_INNER` | `inner_peer` |
| `AETHER_GOOL_MODE` | `protocol=gool` |
| `AETHER_WIW_OUTER_PEER` | `outer_peer` |
| `AETHER_WIW_INNER_PEER` | `inner_peer` |
| `AETHER_MIM_OUTER_PEER` | `outer_peer` |
| `AETHER_MIM_INNER_PEER` | `inner_peer` |
| `AETHER_SCAN` | `scan` |
| `AETHER_NOIZE` | `noize` |
| `AETHER_MASQUE_HTTP2` | `masque_transport` |
| `AETHER_TLS_VERIFY` | `tls_verify` |
| `AETHER_CONFIG` | `config_file` |
| `AETHER_API_ADDRESS` | `enroll_address` |
| `AETHER_PERF_PROFILE` | `perf` |
| `AETHER_LOG_LEVEL` | `log_level` |
| `AETHER_UPSTREAM` | پراکسی بالادستی (`core_upstream`) |
| `AETHER_STATS` | آمار دوره‌ای هسته (`core_stats`) |
| `AETHER_STATS_SECS` | فاصله آمار (ثانیه) (`core_stats_secs`) |
| `AETHER_EXIT_LOC` | فیلتر کشور خروجی (`core_exit_loc`) |
| `AETHER_EXIT_LOC_SECS` | فاصله بررسی کشور خروجی (`core_exit_loc_secs`) |
| `AETHER_TOR_BRIDGES` | پل‌های تور (`core_tor_bridges`) |
| `AETHER_TOR_PT` | ابزارهای پل تور (`core_tor_pt`) |
| `AETHER_TOR_PT_DIR` | پوشه ابزارهای تور (`core_tor_pt_dir`) |
| `AETHER_TOR_HTTP` | نشانی پراکسی HTTP تور (`core_tor_http`) |
| `AETHER_TOR_BRIDGE_FILE` | فایل پل‌های تور (`core_tor_bridge_file`) |
| `AETHER_TOR_RELAYS` | منبع رله‌های تور (`core_tor_relays`) |
| `AETHER_TOR_RELAY_PORTS` | پورت‌های رله تور (`core_tor_relay_ports`) |
| `AETHER_PSIPHON_CONFIG` | فایل تنظیمات سایفون (`core_psiphon_config`) |
| `AETHER_PSIPHON_CDN_IPS` | آدرس‌های CDN سایفون (`core_psiphon_cdn_ips`) |
| `AETHER_PSIPHON_CDN_SNI` | نام‌های سرور CDN سایفون (`core_psiphon_cdn_sni`) |
| `AETHER_PSIPHON_CDN_SETS` | مجموعه‌های CDN سایفون (`core_psiphon_cdn_sets`) |
| `AETHER_PSIPHON_HTTP` | نشانی پراکسی HTTP سایفون (`core_psiphon_http`) |
| `AETHER_PSIPHON_DIR` | پوشه داده‌های سایفون (`core_psiphon_dir`) |
| `AETHER_PSIPHON_BIN` | مسیر فایل اجرایی سایفون (`core_psiphon_bin`) |
| `AETHER_PSIPHON_SERVER_ENTRIES` | فایل سرورهای سایفون (`core_psiphon_server_entries`) |
| `AETHER_PSIPHON_READY_SECS` | مهلت اتصال سایفون (ثانیه) (`core_psiphon_ready_secs`) |
| `AETHER_TOR_DIR` | پوشه داده‌های تور (`core_tor_dir`) |
| `AETHER_TOR_DIRECT_SECS` | مهلت اتصال مستقیم تور (`core_tor_direct_secs`) |
| `AETHER_TOR_STALL_SECS` | مهلت پیشرفت اتصال پل تور (`core_tor_stall_secs`) |
| `AETHER_TOR_BRIDGE_SECS` | مهلت اتصال پل تور (`core_tor_bridge_secs`) |
| `AETHER_TOR_COUNTRY` | کشور درخواست پل تور (`core_tor_country`) |
| `AETHER_TOR_CHECK` | مقصد آزمایش تور (`core_tor_check`) |
| `AETHER_TOR_LOG` | سطح گزارش تور (`core_tor_log`) |
| `AETHER_WG_PEER` | آدرس WireGuard (`core_wg_peer`) |
| `AETHER_WIW_PEERS` | دو لایه WARP در یک مقدار (`core_wiw_peers`) |
| `AETHER_MIM_PEERS` | دو لایه MASQUE در یک مقدار (`core_mim_peers`) |
| `AETHER_QUIC_V2` | آغاز اتصال با QUIC v2 (`core_quic_v2`) |
| `AETHER_MASQUE_H2_PEER` | آدرس انتقال HTTP/2 (`core_masque_h2_peer`) |
| `AETHER_MASQUE_NO_DATA_CHECK` | حذف آزمون عبور داده MASQUE (`core_masque_no_data_check`) |
| `AETHER_WG_NO_DATA_CHECK` | حذف آزمون عبور داده WireGuard (`core_wg_no_data_check`) |
| `AETHER_MASQUE_VALIDATE_SECS` | مهلت اعتبارسنجی MASQUE (`core_masque_validate_secs`) |
| `AETHER_WG_VALIDATE_SECS` | مهلت اعتبارسنجی WireGuard (`core_wg_validate_secs`) |
| `AETHER_MASQUE_STARTUP_SECS` | مهلت راه‌اندازی MASQUE (`core_masque_startup_secs`) |
| `AETHER_MASQUE_RECONNECT_SECS` | فاصله اتصال دوباره MASQUE (`core_masque_reconnect_secs`) |
| `AETHER_WG_RECONNECT_SECS` | فاصله اتصال دوباره WireGuard (`core_wg_reconnect_secs`) |
| `AETHER_DNS` | DNS داخلی اتر (`core_dns`) |
| `AETHER_MASQUE_H2_FRAGMENT` | قطعه‌بندی TLS (`core_masque_h2_fragment`) |
| `AETHER_MASQUE_H2_FRAGMENT_SIZE` | اندازه قطعه‌های TLS (`core_masque_h2_fragment_size`) |
| `AETHER_MASQUE_H2_FRAGMENT_DELAY` | فاصله قطعه‌های TLS (`core_masque_h2_fragment_delay`) |
| `AETHER_MASQUE_SNI` | نام سرور MASQUE (`core_masque_sni`) |
| `AETHER_ECH` | کلید ECH یا auto (`core_ech`) |
| `AETHER_ECH_DNS` | حل‌کننده ECH (`core_ech_dns`) |
| `AETHER_ECH_DOMAIN` | دامنه ECH (`core_ech_domain`) |
| `AETHER_TLS_CIPHERS` | رمزهای TLS 1.2 (`core_tls_ciphers`) |
| `AETHER_TLS13_CIPHERS` | رمزهای TLS 1.3 (`core_tls13_ciphers`) |
| `AETHER_TLS_GROUPS` | گروه‌های TLS (`core_tls_groups`) |
| `AETHER_TLS_KEY_SHARES` | گروه‌های تبادل کلید TLS (`core_tls_key_shares`) |
| `AETHER_DISABLE_GREASE` | غیرفعال‌کردن TLS GREASE (`core_disable_grease`) |
| `AETHER_ENABLE_GREASE_SIGALGS` | GREASE در الگوریتم‌های امضا (`core_enable_grease_sigalgs`) |
| `AETHER_TLS_SIGALGS` | الگوریتم‌های امضای TLS (`core_tls_sigalgs`) |
| `AETHER_TLS_CERT_COMPRESSION` | فشرده‌سازی گواهی TLS (`core_tls_cert_compression`) |
| `AETHER_TLS_ALPS` | نسخه TLS ALPS (`core_tls_alps`) |
| `AETHER_TLS_TRUST_ANCHORS` | شناسه‌های ریشه اعتماد TLS (`core_tls_trust_anchors`) |
| `AETHER_TLS_SERVER_PADDING` | اندازه padding سرور TLS (`core_tls_server_padding`) |
| `AETHER_ENABLE_ECH_GREASE` | فعال‌کردن ECH GREASE (`core_enable_ech_grease`) |
| `AETHER_DISABLE_OCSP_STAPLING` | غیرفعال‌کردن OCSP stapling (`core_disable_ocsp_stapling`) |
| `AETHER_DISABLE_SCT` | غیرفعال‌کردن مهر زمان گواهی (`core_disable_sct`) |
| `AETHER_DISABLE_SESSION_TICKET` | غیرفعال‌کردن بلیت نشست TLS (`core_disable_session_ticket`) |
| `AETHER_DISABLE_EXTENSION_PERMUTATION` | ثابت‌ماندن ترتیب افزونه‌های TLS (`core_disable_extension_permutation`) |
| `AETHER_WG_KEEPALIVE` | فاصله keepalive در WireGuard (`core_wg_keepalive`) |
| `AETHER_WG_NO_PROFILE_RETRY` | غیرفعال‌کردن تکرار با پروفایل دیگر (`core_wg_no_profile_retry`) |
| `AETHER_TEAM` | نام تیم Zero Trust (`core_team`) |
| `AETHER_ACCESS_CLIENT_ID` | شناسه سرویس Zero Trust (`core_access_client_id`) |
| `AETHER_ACCESS_CLIENT_SECRET` | کلید سرویس Zero Trust (`core_access_client_secret`) |
| `AETHER_ACCESS_TOKEN` | توکن Zero Trust (`core_access_token`) |
| `AETHER_ACCESS_EMAIL` | ایمیل Zero Trust (`core_access_email`) |
| `AETHER_GATEWAY` | درگاه سازمانی Zero Trust (`core_gateway`) |
| `AETHER_ROUTE_BLOCK` | مقصدهای مسدود در هسته (`core_route_block`) |
| `AETHER_ROUTE_DIRECT` | مقصدهای مستقیم در هسته (`core_route_direct`) |
| `AETHER_ROUTES_FILE` | فایل قواعد مسیریابی اتر (`core_routes_file`) |
| `AETHER_WG_CONFIG` | فایل هویت WireGuard (`core_wg_config`) |
| `AETHER_MASQUE_CONFIG` | فایل هویت MASQUE (`core_masque_config`) |
| `AETHER_API_SNI` | نام TLS سرویس ثبت WARP (`core_api_sni`) |
| `AETHER_API_HOST` | نام HTTP سرویس ثبت WARP (`core_api_host`) |
| `AETHER_ROUTE_SNIFF` | تشخیص نام سرور برای مسیریابی (`core_route_sniff`) |
| `AETHER_ROUTE_SNIFF_MS` | مهلت تشخیص نام سرور (میلی‌ثانیه) (`core_route_sniff_ms`) |
| `AETHER_WG_ENDPOINT_COOLDOWN_SECS` | مدت کنارگذاشتن سرور WireGuard ناموفق (`core_wg_endpoint_cooldown_secs`) |
| `AETHER_WG_STALE_SECS` | مهلت سکوت WireGuard (`core_wg_stale_secs`) |
| `AETHER_MASQUE_H2_KEEPALIVE_SECS` | فاصله keepalive در HTTP/2 (`core_masque_h2_keepalive_secs`) |
| `AETHER_MASQUE_H2_KEEPALIVE_TIMEOUT_SECS` | مهلت پاسخ keepalive در HTTP/2 (`core_masque_h2_keepalive_timeout_secs`) |
| `AETHER_IRONCLAD_PORT` | پورت آزمایش ironclad (`core_ironclad_port`) |
| `AETHER_MAX_CLIENTS` | حداکثر اتصال‌های پراکسی (`core_max_clients`) |
| `AETHER_HALF_CLOSE_SECS` | مهلت اتصال نیمه‌بسته (`core_half_close_secs`) |
| `AETHER_TCP_KEEPALIVE_SECS` | فاصله keepalive در TCP (`core_tcp_keepalive_secs`) |
| `AETHER_TCP_CONNECT_SECS` | مهلت اتصال TCP (`core_tcp_connect_secs`) |
| `AETHER_REPROVISION` | تعویض هویت WARP ردشده (`core_reprovision`) |
| `AETHER_REGISTER` | دکمه ثبت هویت WARP؛ اجرای جدا از سرویس با حفظ هویت های موجود |
