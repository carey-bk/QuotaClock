#!/usr/bin/env python3
"""Test the shipping updater's state in isolated bundle/defaults domains. Run swift test first."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
candidates = [p.parent for p in (root/'.build').rglob('QuotaCore.swiftmodule') if p.is_file() and list(p.parent.glob('*.o'))]
if not candidates:
    raise SystemExit('Run swift test first to build QuotaCore object files')
objects = candidates[0]
framework = root/'build.noindex/sparkle-tools/Sparkle.framework'
with tempfile.TemporaryDirectory(prefix='quotaclock-reminders-') as folder:
    app = Path(folder)/'Probe.app'
    contents = app/'Contents'
    (contents/'MacOS').mkdir(parents=True)
    (contents/'Frameworks').mkdir()
    subprocess.run(['ditto', str(framework), str(contents/'Frameworks/Sparkle.framework')], check=True)
    info = {'CFBundleIdentifier': 'com.quotaclock.reminders-test', 'CFBundleName':'Update Reminder Test', 'CFBundleExecutable':'Probe', 'CFBundlePackageType':'APPL', 'CFBundleVersion':'99', 'CFBundleShortVersionString':'1.3.0', 'SUFeedURL':'https://example.invalid/appcast.xml', 'SUPublicEDKey':'8xxtAgeWkN9/DA3gYLEPVEOviuXvpNu5jeM2MEd6UaM=', 'SUEnableAutomaticChecks':True, 'SUAutomaticallyUpdate':False}
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    sources = ['Sources/QuotaClockApp/AppUpdater.swift', 'Sources/QuotaClockApp/ReleaseVersionComparison.swift', 'Sources/Shared/AppText.swift', 'Scripts/check-update-reminders.swift']
    subprocess.run(['xcrun','swiftc','-I',str(objects),'-F',str(framework.parent),'-framework','Sparkle','-framework','AppKit','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',*[str(root/p) for p in sources],*[str(p) for p in objects.glob('*.o')],'-o',str(contents/'MacOS/Probe')],check=True)
    subprocess.run(['codesign','--force','--sign','-','--deep',str(app)],check=True)
    for mode in ['fresh','opt-out','cached','installed']:
        subprocess.run([str(contents/'MacOS/Probe'),mode],check=True,timeout=15)
