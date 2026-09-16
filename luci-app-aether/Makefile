# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-aether
PKG_VERSION:=2.1.0
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=dreamboxone

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-aether
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Aether
  PKGARCH:=all
  DEPENDS:=+aether +luci-base +rpcd-mod-file
endef

define Package/luci-app-aether/description
 Persian, right-to-left web interface for the Aether OpenWrt service, with live
 upload and download accounting.
endef

# Same switch as the aether package, sharing its tool: in an OpenWrt build tree
# the two packages sit side by side, so one copy serves both.
AETHER_OBFUSCATE?=0
OBFUSCATE_TOOL:=$(firstword $(wildcard ./tools/obfuscate.py ../aether/tools/obfuscate.py $(TOPDIR)/package/aether/tools/obfuscate.py))

define Build/Prepare
	$(call Build/Prepare/Default)
	rm -rf $(PKG_BUILD_DIR)/htdocs
	$(CP) ./htdocs $(PKG_BUILD_DIR)/htdocs
	$(if $(filter 1,$(AETHER_OBFUSCATE)),$(if $(OBFUSCATE_TOOL),python3 $(OBFUSCATE_TOOL) $(PKG_BUILD_DIR)/htdocs,$(error obfuscate.py not found)))
endef

define Build/Compile
endef

# uhttpd serves /www with an ETag and a Last-Modified and no Cache-Control at
# all, so a browser falls back to heuristic freshness: roughly a tenth of the
# file's age. OpenWrt installs package files with the build timestamp for
# reproducibility, which on a release image is months old, and a tenth of months
# is days. The result is a browser that keeps serving the previous version of
# this page long after the package was upgraded, and is correct to. Stamping the
# installed files with the install time brings that heuristic back to nearly
# nothing, so the next load revalidates.
define Package/luci-app-aether/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
touch /www/luci-static/resources/view/aether/settings.js 	/www/luci-static/resources/view/aether/aether.css 2>/dev/null
exit 0
endef

define Package/luci-app-aether/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/aether
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/aether/settings.js $(1)/www/luci-static/resources/view/aether/settings.js
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/aether/aether.css $(1)/www/luci-static/resources/view/aether/aether.css
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-aether.json $(1)/usr/share/luci/menu.d/luci-app-aether.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-aether.json $(1)/usr/share/rpcd/acl.d/luci-app-aether.json
endef

$(eval $(call BuildPackage,luci-app-aether))
