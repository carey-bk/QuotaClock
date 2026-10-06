#!/usr/bin/env python3
"""Build a Finder-layout DMG. Run with the dmgbuild environment in build.noindex/dmg-tools."""
from pathlib import Path
import argparse, plistlib, subprocess
import dmgbuild

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--products', type=Path, default=root/'build.noindex/Build/Products/Release')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
app = args.products/'QuotaClock.app'
saver = args.products/'QuotaClock.saver'
with (app/'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
output = args.output or Path.home()/'Desktop'/f'QuotaClock-{version}-{build}.dmg'
if output.exists(): raise SystemExit(f'Refusing to overwrite {output}')
art = root/'build.noindex/dmg-artwork'; art.mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', str(root/'Scripts/dmg-background.swift'), str(art)], check=True)
for bundle in (app, saver): subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
dmgbuild.build_dmg(str(output), f'QuotaClock {version}', settings={
    'files': [str(app), str(saver)], 'symlinks': {'Applications': '/Applications'},
    'background': str(art/'installer.png'), 'format': 'UDZO',
    'window_rect': ((180, 100), (800, 680)), 'icon_size': 128, 'text_size': 14,
    'icon_locations': {'QuotaClock.app': (210, 238), 'Applications': (590, 238), 'QuotaClock.saver': (155, 460)},
    'show_status_bar': False, 'show_toolbar': False, 'show_sidebar': False,
    'show_pathbar': False, 'show_tab_view': False, 'default_view': 'icon-view',
    'include_icon_view_settings': True, 'include_list_view_settings': False,
})
print(output)
