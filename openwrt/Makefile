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
  DEPENDS:=+ca-bundle +libustream-mbedtls +ip-full +nftables +kmod-nft-tproxy \
	+kmod-nft-socket +kmod-tun +sing-box
endef

define Package/aether/description
 Aether SOCKS5 service with optional transparent LAN proxying, TUN mode, Iran
 bypass and sing-box rule sets. Installing it pulls in sing-box, the nftables
 TProxy and socket kernel modules, the TUN module and full iproute2, so a fresh
 router has everything transparent mode needs.
endef

define Build/Compile
endef

AETHER_BINARY?=$(CURDIR)/prebuilt/$(ARCH)/aether

# AETHER_OBFUSCATE=1 on the make command line strips the shipped shell scripts
# down to working code with their licence headers, and nothing else, before they
# are installed. See tools/obfuscate.py for what that does and does not buy.
AETHER_OBFUSCATE?=0

define Build/Prepare
	$(call Build/Prepare/Default)
	@test -f "$(AETHER_BINARY)" || (echo "Missing Aether binary: $(AETHER_BINARY)" >&2; exit 1)
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
mkdir -p /etc/aether/geo
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
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/libexec/aether/deps.sh $(1)/usr/libexec/aether/deps.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/aether $(1)/etc/init.d/aether
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/aether $(1)/etc/config/aether
	$(INSTALL_DIR) $(1)/etc/aether/geo
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/aether/iran4.txt $(1)/etc/aether/iran4.txt
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/aether/iran6.txt $(1)/etc/aether/iran6.txt
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/90-aether $(1)/etc/uci-defaults/90-aether
endef

$(eval $(call BuildPackage,aether))
