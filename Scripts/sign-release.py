#!/usr/bin/env python3
"""Sign release components inside-out, with Developer ID and secure timestamps.
Run after xcodebuild and before notarization / packaging.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', type=Path, default=Path('build.noindex/Build/Products/Release'))
parser.add_argument('--identity', default='Developer ID Application')
args = parser.parse_args()
app = args.products / 'QuotaClock.app'
framework = app / 'Contents/Frameworks/Sparkle.framework'
b = framework / 'Versions/B'
components = [b / 'Autoupdate', b / 'Updater.app',
              b / 'XPCServices/Downloader.xpc', b / 'XPCServices/Installer.xpc', framework,
              app / 'Contents/PlugIns/QuotaWidget.appex',
              app / 'Contents/Resources/QuotaClock.saver', app,
              args.products / 'QuotaClock.saver']
for component in components:
    subprocess.run(['codesign', '--force', '--sign', args.identity, '--timestamp',
                    '--options', 'runtime', '--preserve-metadata=identifier,entitlements',
                    str(component)], check=True)
for component in [app, args.products / 'QuotaClock.saver']:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(component)], check=True)
print('Release signatures verified. Submit for notarization before distribution.')
