# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-aether
PKG_VERSION:=2.1.0
PKG_RELEASE:=3
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=dreamboxone

include $(INCLUDE_DIR)/package.mk

# The view is installed under a name carrying the release, and the menu entry is
# rewritten to match. LuCI stamps its own version onto the URL it fetches a view
# from, which never changes when only this package does, so a browser holding an
# older copy keeps using it — and with the caching uhttpd advertises (see the
# postinst below) it holds one for days. A new release is a new URL, so the page
# a user opens is the page that was installed.
#
# The dots go. A view name is a class name to LuCI, which turns every dot into a
# path separator, so "settings-2.1.0-r1" is fetched as "settings-2/1/0-r1.js"
# and the page dies with a 404 before it renders anything.
VIEW:=settings-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)

# The stylesheet gets the same treatment, and for a sharper reason: a ?v= query
# carrying the version only changes when the version does, so a stylesheet edited
# between two builds of the same release keeps the URL it already had, and a
# browser that fetched the earlier one goes on serving it. A file name derived
# from the release moves whenever the package does.
CSS:=aether-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE).css

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
touch /www/luci-static/resources/view/aether/*.js 	/www/luci-static/resources/view/aether/*.css 2>/dev/null
exit 0
endef

define Package/luci-app-aether/install
	@case "$(VIEW)" in *.*) 		echo "view name must not contain a dot, LuCI reads it as a path: $(VIEW)" >&2; 		exit 1 ;; esac
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/aether
	sed 's#view/aether/aether\.css#view/aether/$(CSS)#' 		$(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/aether/settings.js 		> $(1)/www/luci-static/resources/view/aether/$(VIEW).js
	chmod 0644 $(1)/www/luci-static/resources/view/aether/$(VIEW).js
	@grep -q 'view/aether/$(CSS)' $(1)/www/luci-static/resources/view/aether/$(VIEW).js || 		{ echo "the stylesheet reference was not rewritten" >&2; exit 1; }
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/aether/aether.css $(1)/www/luci-static/resources/view/aether/$(CSS)
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	sed 's#aether/settings#aether/$(VIEW)#' ./root/usr/share/luci/menu.d/luci-app-aether.json 		> $(1)/usr/share/luci/menu.d/luci-app-aether.json
	chmod 0644 $(1)/usr/share/luci/menu.d/luci-app-aether.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-aether.json $(1)/usr/share/rpcd/acl.d/luci-app-aether.json
endef

$(eval $(call BuildPackage,luci-app-aether))
