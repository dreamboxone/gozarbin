# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

include $(TOPDIR)/rules.mk

PKG_NAME:=gozarbin
PKG_VERSION:=5.8.21
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=dreamboxone

include $(INCLUDE_DIR)/package.mk
include $(CURDIR)/luci.mk

LUCI_SOURCE:=$(firstword $(wildcard $(CURDIR)/luci $(CURDIR)/../luci-app-gozarbin))

define Package/gozarbin
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Gozarbin censorship-circumvention client for OpenWrt
  URL:=https://github.com/dreamboxone/gozarbin
  PROVIDES:=luci-app-gozarbin
  REPLACES:=luci-app-gozarbin
  # No +sing-box here on purpose. On a router with Passwall2 that package is
  # Passwall2's own core, and depending on it would tie Gozarbin's upgrades to it.
  # Gozarbin installs a core of its own instead; see files/usr/libexec/gozarbin/singbox.sh.
  DEPENDS:=+luci-base +rpcd-mod-file +ca-bundle +libustream-mbedtls +ip-full +nftables +kmod-nft-tproxy \
	+kmod-nft-socket +kmod-tun +curl +jsonfilter +ucode +ucode-mod-fs
endef

define Package/gozarbin/description
 SOCKS5 service built on the Aether core, with optional transparent LAN proxying, TUN mode, Iran
 bypass, sing-box rule sets and Psiphon with a choice of exit country. Installing it pulls in the nftables TProxy and
 socket kernel modules, the TUN module and full iproute2. Transparent mode also
 needs a sing-box core, which Gozarbin keeps its own copy of and installs from
 SagerNet's releases: a sing-box belonging to Passwall2 is never used here, and
 never upgraded.
endef

define Build/Compile
endef

# ARCH_PACKAGES, not ARCH. ARCH is the CPU family — "arm" covers armv5, armv6
# and both armv7 ABIs, which need four different binaries — while ARCH_PACKAGES
# is the package architecture OpenWrt actually distributes against, such as
# arm_cortex-a7_neon-vfpv4. ARCH remains a fallback for a tree that predates it.
GOZARBIN_BINARY?=$(firstword $(wildcard 	$(CURDIR)/prebuilt/$(ARCH_PACKAGES)/aether 	$(CURDIR)/prebuilt/$(ARCH)/aether))
GOZARBIN_PT?=$(firstword $(wildcard $(CURDIR)/prebuilt/$(ARCH_PACKAGES)/pt/lyrebird $(CURDIR)/prebuilt/$(ARCH)/pt/lyrebird))
# Psiphon ships inside the package, so one install has every transport. It is
# some twenty megabytes on flash; a target built without a binary simply has no
# Psiphon, and the service runs as if it were switched off.
GOZARBIN_PSIPHON?=$(firstword $(wildcard $(CURDIR)/prebuilt/$(ARCH_PACKAGES)/pt/psiphon-tunnel-core $(CURDIR)/prebuilt/$(ARCH)/pt/psiphon-tunnel-core))

# GOZARBIN_OBFUSCATE=1 on the make command line strips the shipped shell scripts
# down to working code with their licence headers, and nothing else, before they
# are installed. See tools/obfuscate.py for what that does and does not buy.
GOZARBIN_OBFUSCATE?=0

define Build/Prepare
	$(call Build/Prepare/Default)
	@test -n "$(GOZARBIN_BINARY)" -a -f "$(GOZARBIN_BINARY)" || 		(echo "No tunnel core for this target: looked for prebuilt/$(ARCH_PACKAGES)/aether and prebuilt/$(ARCH)/aether" >&2; exit 1)
	$(CP) ./LICENSE ./NOTICE $(PKG_BUILD_DIR)/
	$(CP) "$(GOZARBIN_BINARY)" $(PKG_BUILD_DIR)/aether
	$(if $(GOZARBIN_PT),$(CP) "$(GOZARBIN_PT)" $(PKG_BUILD_DIR)/lyrebird)
	$(if $(GOZARBIN_PSIPHON),$(CP) "$(GOZARBIN_PSIPHON)" $(PKG_BUILD_DIR)/psiphon-tunnel-core)
	echo "$(PKG_VERSION)-r$(PKG_RELEASE)" > $(PKG_BUILD_DIR)/version
	rm -rf $(PKG_BUILD_DIR)/files
	$(CP) ./files $(PKG_BUILD_DIR)/files
	@test -d "$(LUCI_SOURCE)/htdocs" || { echo "LuCI sources are required for the unified package" >&2; exit 1; }
	rm -rf $(PKG_BUILD_DIR)/luci
	$(CP) "$(LUCI_SOURCE)" $(PKG_BUILD_DIR)/luci
	$(if $(filter 1,$(GOZARBIN_OBFUSCATE)),python3 ./tools/obfuscate.py $(PKG_BUILD_DIR)/files $(PKG_BUILD_DIR)/luci/htdocs)
endef

define Package/gozarbin/conffiles
/etc/config/gozarbin
endef

define Package/gozarbin/prerm
#!/bin/sh
[ -x /etc/init.d/gozarbin ] && /etc/init.d/gozarbin stop
exit 0
endef

define Package/gozarbin/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
mkdir -p /etc/gozarbin/geo /etc/gozarbin/state
# Up to 2.2.x Psiphon came in gozarbin-psiphon, under pt/. This package now
# carries its own copy, so the old one is twenty megabytes of dead weight on
# flash; drop it and say how to remove the empty package left behind.
if [ -x /usr/libexec/gozarbin/psiphon-tunnel-core ] && [ -f /usr/libexec/gozarbin/pt/psiphon-tunnel-core ]; then
	rm -f /usr/libexec/gozarbin/pt/psiphon-tunnel-core
	if command -v apk >/dev/null 2>&1; then
		echo "Gozarbin: Psiphon is part of this package now; remove the empty old one with: apk del gozarbin-psiphon"
	else
		echo "Gozarbin: Psiphon is part of this package now; remove the empty old one with: opkg remove gozarbin-psiphon"
	fi
fi
touch /www/luci-static/resources/view/gozarbin/*.js /www/luci-static/resources/view/gozarbin/*.css 2>/dev/null
rm -f /tmp/luci-indexcache.*.json
if [ -x /etc/init.d/rpcd ]; then
	setsid /bin/sh -c 'sleep 2; /etc/init.d/rpcd reload' </dev/null >/dev/null 2>&1 &
fi
missing=$(/usr/libexec/gozarbin/deps.sh --missing 2>/dev/null)
[ -n "$$missing" ] && echo "Gozarbin: these dependencies are still missing:$$missing"
exit 0
endef

define Package/gozarbin/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/usr/libexec/gozarbin/cores/aether/bundled/pt
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aether $(1)/usr/libexec/gozarbin/cores/aether/bundled/gozarbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/gozarbin $(1)/usr/bin/gozarbin
	$(if $(GOZARBIN_PT),$(INSTALL_BIN) $(PKG_BUILD_DIR)/lyrebird $(1)/usr/libexec/gozarbin/cores/aether/bundled/pt/lyrebird)
	$(INSTALL_DIR) $(1)/usr/libexec/gozarbin
	# Not under pt/, where gozarbin-psiphon kept it: opkg refuses to install a
	# file another package still owns, so a router upgrading with the old package
	# on board would fail. A new path never clashes; postinst drops the old copy.
	$(if $(GOZARBIN_PSIPHON),$(INSTALL_BIN) $(PKG_BUILD_DIR)/psiphon-tunnel-core $(1)/usr/libexec/gozarbin/cores/aether/bundled/pt/psiphon-tunnel-core)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/gozarbinctl $(1)/usr/bin/gozarbinctl
	$(INSTALL_DIR) $(1)/usr/share/licenses/gozarbin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/gozarbin/LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/NOTICE $(1)/usr/share/licenses/gozarbin/NOTICE
	$(INSTALL_DIR) $(1)/usr/share/gozarbin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/version $(1)/usr/share/gozarbin/version
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/share/gozarbin/core-options.json $(1)/usr/share/gozarbin/core-options.json
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/share/gozarbin/aether-upstream-version $(1)/usr/share/gozarbin/aether-upstream-version
	$(INSTALL_DIR) $(1)/usr/libexec/gozarbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/aether-core.sh $(1)/usr/libexec/gozarbin/aether-core.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/singbox-core.sh $(1)/usr/libexec/gozarbin/singbox-core.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/geo-core.sh $(1)/usr/libexec/gozarbin/geo-core.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/update.sh $(1)/usr/libexec/gozarbin/update.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/releases.sh $(1)/usr/libexec/gozarbin/releases.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/history.sh $(1)/usr/libexec/gozarbin/history.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/history.uc $(1)/usr/libexec/gozarbin/history.uc
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/delta.sh $(1)/usr/libexec/gozarbin/delta.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/delta-plan.uc $(1)/usr/libexec/gozarbin/delta-plan.uc
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/firewall.sh $(1)/usr/libexec/gozarbin/firewall.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/passwall2-detect.sh $(1)/usr/libexec/gozarbin/passwall2-detect.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/system-info.sh $(1)/usr/libexec/gozarbin/system-info.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/dns.sh $(1)/usr/libexec/gozarbin/dns.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/fetch.sh $(1)/usr/libexec/gozarbin/fetch.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/geo-update.sh $(1)/usr/libexec/gozarbin/geo-update.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/traffic.sh $(1)/usr/libexec/gozarbin/traffic.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/tunnel.sh $(1)/usr/libexec/gozarbin/tunnel.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/logs.sh $(1)/usr/libexec/gozarbin/logs.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/dashboard.sh $(1)/usr/libexec/gozarbin/dashboard.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/connectivity.sh $(1)/usr/libexec/gozarbin/connectivity.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/deps.sh $(1)/usr/libexec/gozarbin/deps.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/packages.sh $(1)/usr/libexec/gozarbin/packages.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/singbox.sh $(1)/usr/libexec/gozarbin/singbox.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/monitor.sh $(1)/usr/libexec/gozarbin/monitor.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/gozarbin $(1)/etc/init.d/gozarbin
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/gozarbin $(1)/etc/config/gozarbin
	$(INSTALL_DIR) $(1)/etc/gozarbin/geo
	$(INSTALL_DIR) $(1)/etc/gozarbin/state
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/90-gozarbin $(1)/etc/uci-defaults/90-gozarbin
	$(call Gozarbin/InstallLuCI,$(1))
endef

$(eval $(call BuildPackage,gozarbin))
