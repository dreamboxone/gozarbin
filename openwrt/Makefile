# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

include $(TOPDIR)/rules.mk

PKG_NAME:=gozarbin
PKG_VERSION:=2.1.0
PKG_RELEASE:=4
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=dreamboxone

include $(INCLUDE_DIR)/package.mk

define Package/gozarbin
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Gozarbin censorship-circumvention client for OpenWrt
  URL:=https://github.com/dreamboxone/gozarbin
  # No +sing-box here on purpose. On a router with Passwall2 that package is
  # Passwall2's own core, and depending on it would tie Gozarbin's upgrades to it.
  # Gozarbin installs a core of its own instead; see files/usr/libexec/gozarbin/singbox.sh.
  DEPENDS:=+ca-bundle +libustream-mbedtls +ip-full +nftables +kmod-nft-tproxy \
	+kmod-nft-socket +kmod-tun
endef

define Package/gozarbin/description
 SOCKS5 service built on the Aether core, with optional transparent LAN proxying, TUN mode, Iran
 bypass and sing-box rule sets. Installing it pulls in the nftables TProxy and
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

# GOZARBIN_OBFUSCATE=1 on the make command line strips the shipped shell scripts
# down to working code with their licence headers, and nothing else, before they
# are installed. See tools/obfuscate.py for what that does and does not buy.
GOZARBIN_OBFUSCATE?=0

define Build/Prepare
	$(call Build/Prepare/Default)
	@test -n "$(GOZARBIN_BINARY)" -a -f "$(GOZARBIN_BINARY)" || 		(echo "No tunnel core for this target: looked for prebuilt/$(ARCH_PACKAGES)/aether and prebuilt/$(ARCH)/aether" >&2; exit 1)
	$(CP) "$(GOZARBIN_BINARY)" $(PKG_BUILD_DIR)/aether
	echo "$(PKG_VERSION)-r$(PKG_RELEASE)" > $(PKG_BUILD_DIR)/version
	rm -rf $(PKG_BUILD_DIR)/files
	$(CP) ./files $(PKG_BUILD_DIR)/files
	$(if $(filter 1,$(GOZARBIN_OBFUSCATE)),python3 ./tools/obfuscate.py $(PKG_BUILD_DIR)/files)
endef

define Package/gozarbin/conffiles
/etc/config/gozarbin
/etc/gozarbin/iran4.txt
/etc/gozarbin/iran6.txt
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
missing=$$(/usr/libexec/gozarbin/deps.sh --missing 2>/dev/null)
[ -n "$$missing" ] && echo "Gozarbin: these dependencies are still missing:$$missing"
exit 0
endef

define Package/gozarbin/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aether $(1)/usr/bin/gozarbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/gozarbinctl $(1)/usr/bin/gozarbinctl
	$(INSTALL_DIR) $(1)/usr/share/gozarbin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/version $(1)/usr/share/gozarbin/version
	$(INSTALL_DIR) $(1)/usr/libexec/gozarbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/firewall.sh $(1)/usr/libexec/gozarbin/firewall.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/passwall2-detect.sh $(1)/usr/libexec/gozarbin/passwall2-detect.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/system-info.sh $(1)/usr/libexec/gozarbin/system-info.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/update-iran.sh $(1)/usr/libexec/gozarbin/update-iran.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/geo-update.sh $(1)/usr/libexec/gozarbin/geo-update.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/traffic.sh $(1)/usr/libexec/gozarbin/traffic.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/gozarbin/tunnel.sh $(1)/usr/libexec/gozarbin/tunnel.sh
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
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/gozarbin/iran4.txt $(1)/etc/gozarbin/iran4.txt
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/gozarbin/iran6.txt $(1)/etc/gozarbin/iran6.txt
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/90-gozarbin $(1)/etc/uci-defaults/90-gozarbin
endef

$(eval $(call BuildPackage,gozarbin))
