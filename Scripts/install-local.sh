#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
products="$PWD/build.noindex/Build/Products/Debug"
backup="$PWD/build.noindex/install-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/Applications" "$HOME/Library/Screen Savers"
# WidgetKit can keep an extension executable from a previous bundle alive after
# replacement. End only QuotaClock's extension processes before moving the app.
/usr/bin/killall QuotaWidget 2>/dev/null || true
# Direct xcodebuild invocations also register the build product. Keep the
# installed bundle as the sole discoverable Widget after every install path.
/usr/bin/pluginkit -r "$products/QuotaClock.app/Contents/PlugIns/QuotaWidget.appex" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$products/QuotaClock.app" 2>/dev/null || true
for pair in app saver; do
  if [[ "$pair" == app ]]; then
    source="$products/QuotaClock.app"
    destination="$HOME/Applications/QuotaClock.app"
  else
    source="$products/QuotaClock.saver"
    destination="$HOME/Library/Screen Savers/QuotaClock.saver"
  fi
  /usr/bin/codesign --verify --strict "$source"
  if [[ -e "$destination" ]]; then
    if [[ "$pair" == app ]]; then
      /usr/bin/pluginkit -r "$destination/Contents/PlugIns/QuotaWidget.appex" 2>/dev/null || true
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$destination" 2>/dev/null || true
    fi
    mkdir -p "$backup"
    mv "$destination" "$backup/"
  fi
  /usr/bin/ditto "$source" "$destination"
  /usr/bin/codesign --verify --strict "$destination"
done
# Backups are recoverable bundles, but Spotlight may discover them as runnable
# apps and make the launch target ambiguous. Keep them on disk, unregister them.
for old_app in "$PWD"/build.noindex/install-backups/*/QuotaClock.app(N); do
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$old_app" 2>/dev/null || true
done
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$HOME/Applications/QuotaClock.app"
/usr/bin/pluginkit -a "$HOME/Applications/QuotaClock.app/Contents/PlugIns/QuotaWidget.appex"
expected_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$HOME/Applications/QuotaClock.app/Contents/PlugIns/QuotaWidget.appex/Contents/Info.plist")
registered=false
for attempt in {1..20}; do
  if /usr/bin/pluginkit -m -A -D -v -i com.quotaclock.app.providerwidget 2>/dev/null | /usr/bin/grep -F "com.quotaclock.app.providerwidget($expected_version)" >/dev/null; then registered=true; break; fi
  /bin/sleep 0.2
done
[[ "$registered" == true ]] || { print -u2 'Widget extension did not register'; exit 1; }
/usr/bin/pluginkit -m -A -D -v -i com.quotaclock.app.providerwidget
# chronod may keep gallery/desktop archives for the old executable even after
# PluginKit has registered the new bundle. It relaunches automatically.
/usr/bin/killall chronod 2>/dev/null || true
print 'Installed ~/Applications/QuotaClock.app and ~/Library/Screen Savers/QuotaClock.saver'
print 'Launch the app, add a Small, Medium, or Large desktop widget, and select QuotaClock in Screen Saver settings.'
print 'This script does not change your active screen saver or lock settings.'
