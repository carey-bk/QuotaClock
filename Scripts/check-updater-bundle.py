#!/usr/bin/env python3
"""Validate the shipping updater configuration and bundled component identities."""
import base64
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['SUFeedURL'] == 'https://github.com/carey-bk/QuotaClock/releases/latest/download/appcast.xml'
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
assert info['SUEnableAutomaticChecks'] is True
assert info['SUAutomaticallyUpdate'] is False
assert info['SUSendProfileInfo'] is False
assert info['SUScheduledCheckInterval'] == 86400
assert info['SUVerifyUpdateBeforeExtraction'] is True
for relative, identifier in [
    ('Contents/PlugIns/QuotaWidget.appex', 'com.quotaclock.app.providerwidget'),
    ('Contents/Resources/QuotaClock.saver', 'com.quotaclock.saver'),
]:
    bundle = app/relative
    child = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    assert child['CFBundleIdentifier'] == identifier
    assert child['CFBundleVersion'] == info['CFBundleVersion']
    assert child['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
assert (app/'Contents/Frameworks/Sparkle.framework').exists()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('PASS: HTTPS feed, public signing key, daily checks, confirmation before downloads, signed app/widget/saver, matching versions')
