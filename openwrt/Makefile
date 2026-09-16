# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

include $(TOPDIR)/rules.mk

PKG_NAME:=aether
PKG_VERSION:=2.1.0
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=dreamboxone

include $(INCLUDE_DIR)/package.mk

define Package/aether
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Aether censorship-circumvention client for OpenWrt
  URL:=https://github.com/dreamboxone/aether
  # No +sing-box here on purpose. On a router with Passwall2 that package is
  # Passwall2's own core, and depending on it would tie Aether's upgrades to it.
  # Aether installs a core of its own instead; see files/usr/libexec/aether/singbox.sh.
  DEPENDS:=+ca-bundle +libustream-mbedtls +ip-full +nftables +kmod-nft-tproxy \
	+kmod-nft-socket +kmod-tun
endef

define Package/aether/description
 Aether SOCKS5 service with optional transparent LAN proxying, TUN mode, Iran
 bypass and sing-box rule sets. Installing it pulls in the nftables TProxy and
 socket kernel modules, the TUN module and full iproute2. Transparent mode also
 needs a sing-box core, which Aether keeps its own copy of and installs from
 SagerNet's releases: a sing-box belonging to Passwall2 is never used here, and
 never upgraded.
endef

define Build/Compile
endef

# ARCH_PACKAGES, not ARCH. ARCH is the CPU family — "arm" covers armv5, armv6
# and both armv7 ABIs, which need four different binaries — while ARCH_PACKAGES
# is the package architecture OpenWrt actually distributes against, such as
# arm_cortex-a7_neon-vfpv4. ARCH remains a fallback for a tree that predates it.
AETHER_BINARY?=$(firstword $(wildcard 	$(CURDIR)/prebuilt/$(ARCH_PACKAGES)/aether 	$(CURDIR)/prebuilt/$(ARCH)/aether))

# AETHER_OBFUSCATE=1 on the make command line strips the shipped shell scripts
# down to working code with their licence headers, and nothing else, before they
# are installed. See tools/obfuscate.py for what that does and does not buy.
AETHER_OBFUSCATE?=0

define Build/Prepare
	$(call Build/Prepare/Default)
	@test -n "$(AETHER_BINARY)" -a -f "$(AETHER_BINARY)" || 		(echo "No Aether binary for this target: looked for prebuilt/$(ARCH_PACKAGES)/aether and prebuilt/$(ARCH)/aether" >&2; exit 1)
	$(CP) "$(AETHER_BINARY)" $(PKG_BUILD_DIR)/aether
	echo "$(PKG_VERSION)-r$(PKG_RELEASE)" > $(PKG_BUILD_DIR)/version
	rm -rf $(PKG_BUILD_DIR)/files
	$(CP) ./files $(PKG_BUILD_DIR)/files
	$(if $(filter 1,$(AETHER_OBFUSCATE)),python3 ./tools/obfuscate.py $(PKG_BUILD_DIR)/files)
endef

define Package/aether/conffiles
/etc/config/aether
/etc/aether/iran4.txt
/etc/aether/iran6.txt
endef

define Package/aether/prerm
#!/bin/sh
[ -x /etc/init.d/aether ] && /etc/init.d/aether stop
exit 0
endef

define Package/aether/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
mkdir -p /etc/aether/geo /etc/aether/state
missing=$$(/usr/libexec/aether/deps.sh --missing 2>/dev/null)
[ -n "$$missing" ] && echo "Aether: these dependencies are still missing:$$missing"
exit 0
endef

define Package/aether/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aether $(1)/usr/bin/aether
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/aetherctl $(1)/usr/bin/aetherctl
	$(INSTALL_DIR) $(1)/usr/share/aether
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/version $(1)/usr/share/aether/version
	$(INSTALL_DIR) $(1)/usr/libexec/aether
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/firewall.sh $(1)/usr/libexec/aether/firewall.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/passwall2-detect.sh $(1)/usr/libexec/aether/passwall2-detect.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/system-info.sh $(1)/usr/libexec/aether/system-info.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/update-iran.sh $(1)/usr/libexec/aether/update-iran.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/geo-update.sh $(1)/usr/libexec/aether/geo-update.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/traffic.sh $(1)/usr/libexec/aether/traffic.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/tunnel.sh $(1)/usr/libexec/aether/tunnel.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/deps.sh $(1)/usr/libexec/aether/deps.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/libexec/aether/packages.sh $(1)/usr/libexec/aether/packages.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/singbox.sh $(1)/usr/libexec/aether/singbox.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/monitor.sh $(1)/usr/libexec/aether/monitor.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/aether $(1)/etc/init.d/aether
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/aether $(1)/etc/config/aether
	$(INSTALL_DIR) $(1)/etc/aether/geo
	$(INSTALL_DIR) $(1)/etc/aether/state
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/aether/iran4.txt $(1)/etc/aether/iran4.txt
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/aether/iran6.txt $(1)/etc/aether/iran6.txt
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/90-aether $(1)/etc/uci-defaults/90-aether
endef

$(eval $(call BuildPackage,aether))
