# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

VIEW:=settings-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)
UPDATE_VIEW:=update-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)
APPEARANCE:=appearance-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)
TRAFFIC:=traffic-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)
I18N:=i18n-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)
CORE_UPDATE:=core-update-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE)

# The stylesheet gets the same treatment, and for a sharper reason: a ?v= query
# carrying the version only changes when the version does, so a stylesheet edited
# between two builds of the same release keeps the URL it already had, and a
# browser that fetched the earlier one goes on serving it. A file name derived
# from the release moves whenever the package does.
CSS:=gozarbin-$(subst .,-,$(PKG_VERSION))-r$(PKG_RELEASE).css

define Gozarbin/InstallLuCI
	@case "$(VIEW)" in *.*) 		echo "view name must not contain a dot, LuCI reads it as a path: $(VIEW)" >&2; 		exit 1 ;; esac
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/gozarbin
	sed -e 's#view.gozarbin.i18n as#view.gozarbin.$(I18N) as#' -e 's#view/gozarbin/gozarbin\.css#view/gozarbin/$(CSS)#' -e 's#view.gozarbin.appearance as#view.gozarbin.$(APPEARANCE) as#' -e 's#view.gozarbin.traffic as#view.gozarbin.$(TRAFFIC) as#' $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/settings.js > $(1)/www/luci-static/resources/view/gozarbin/$(VIEW).js
	chmod 0644 $(1)/www/luci-static/resources/view/gozarbin/$(VIEW).js
	sed -e 's#view.gozarbin.i18n as#view.gozarbin.$(I18N) as#' -e 's#view/gozarbin/gozarbin\.css#view/gozarbin/$(CSS)#' -e 's#view.gozarbin.appearance as#view.gozarbin.$(APPEARANCE) as#' -e 's#view.gozarbin.core-update as#view.gozarbin.$(CORE_UPDATE) as#' $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/update.js > $(1)/www/luci-static/resources/view/gozarbin/$(UPDATE_VIEW).js
	chmod 0644 $(1)/www/luci-static/resources/view/gozarbin/$(UPDATE_VIEW).js
	sed -e 's#view.gozarbin.i18n as#view.gozarbin.$(I18N) as#' $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/appearance.js > $(1)/www/luci-static/resources/view/gozarbin/$(APPEARANCE).js
	sed -e 's#view.gozarbin.i18n as#view.gozarbin.$(I18N) as#' -e 's#view.gozarbin.appearance as#view.gozarbin.$(APPEARANCE) as#' $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/traffic.js > $(1)/www/luci-static/resources/view/gozarbin/$(TRAFFIC).js
	sed -e 's#view.gozarbin.i18n as#view.gozarbin.$(I18N) as#' $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/core-update.js > $(1)/www/luci-static/resources/view/gozarbin/$(CORE_UPDATE).js
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/i18n.js $(1)/www/luci-static/resources/view/gozarbin/$(I18N).js
	@grep -q 'view/gozarbin/$(CSS)' $(1)/www/luci-static/resources/view/gozarbin/$(VIEW).js || 		{ echo "the stylesheet reference was not rewritten" >&2; exit 1; }
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/gozarbin.css $(1)/www/luci-static/resources/view/gozarbin/$(CSS)
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/logo.png $(1)/www/luci-static/resources/view/gozarbin/logo.png
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/gozarbin/fonts
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/gozarbin/fonts/* $(1)/www/luci-static/resources/view/gozarbin/fonts/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	sed -e 's#"gozarbin/settings"#"gozarbin/$(VIEW)"#' -e 's#"gozarbin/update"#"gozarbin/$(UPDATE_VIEW)"#' $(PKG_BUILD_DIR)/luci/root/usr/share/luci/menu.d/luci-app-gozarbin.json > $(1)/usr/share/luci/menu.d/luci-app-gozarbin.json
	chmod 0644 $(1)/usr/share/luci/menu.d/luci-app-gozarbin.json
	$(INSTALL_DIR) $(1)/usr/share/licenses/gozarbin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/COPYRIGHT $(1)/usr/share/licenses/gozarbin/LUCI-COPYRIGHT
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/rpcd/acl.d/luci-app-gozarbin.json $(1)/usr/share/rpcd/acl.d/luci-app-gozarbin.json
endef
