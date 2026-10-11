#!/usr/bin/env python3
"""Run real Sparkle feed selection in disposable app hosts without downloading updates."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parent.parent
framework = root/'build.noindex/sparkle-tools/Sparkle.framework'
probe = root/'build.noindex/check-updater-feed'
subprocess.run(['xcrun', 'swiftc', '-D', 'VERSION_POLICY_PROBE', str(root/'Sources/QuotaCore/AppVersion.swift'), str(root/'Sources/QuotaClockApp/ReleaseVersionComparison.swift'), '-F', str(framework.parent), '-framework', 'Sparkle', '-framework', 'AppKit', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', str(root/'Scripts/check-updater-feed.swift'), '-o', str(probe)], check=True)
class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
with tempfile.TemporaryDirectory(prefix='quotaclock-update-test-') as temporary:
    directory = Path(temporary)
    # Feed-selection fixture only: no archive download or signature claim.
    (directory/'appcast.xml').write_text('''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Test</title><item><title>1.0</title><sparkle:version>80</sparkle:version><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString><enclosure url="https://example.invalid/update.zip" length="100" type="application/octet-stream"/></item></channel></rss>''')
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=temporary))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        for name, version, marketing, remote, path, expected in [
            ('older', '79', '0.9.0', '1.0.0', 'appcast.xml', 'UPDATE 80'),
            ('current', '79', '1.0.0', '1.0.0', 'appcast.xml', 'CURRENT'),
            ('numeric', '79', '2.2.9', 'v2.2.10', 'appcast.xml', 'UPDATE 80'),
            ('timestamp', '20261010.161843', '2.2.9', '2.2.10', 'appcast.xml', 'UPDATE 80'),
            ('newer-dev', '79', '1.2.0-beta.12', '1.1.0', 'appcast.xml', 'CURRENT'),
            ('same-beta', '79', '1.2.0-beta.12', '1.2.0', 'appcast.xml', 'CURRENT'),
            ('legacy', '79', '0.9.0', 'v1.0', 'appcast.xml', 'UPDATE 80'),
            ('unavailable', '80', '1.0.0', '1.0.0', 'missing.xml', 'ERROR')]:
            feed = (directory/'appcast.xml').read_text()
            import re
            feed = re.sub(r'<sparkle:shortVersionString>.*?</sparkle:shortVersionString>', f'<sparkle:shortVersionString>{remote}</sparkle:shortVersionString>', feed)
            (directory/'appcast.xml').write_text(feed)
            app = directory/(name+'.app'); contents = app/'Contents'
            (contents/'MacOS').mkdir(parents=True); (contents/'Frameworks').mkdir()
            shutil.copy2(probe, contents/'MacOS/Probe')
            subprocess.run(['ditto', str(framework), str(contents/'Frameworks/Sparkle.framework')], check=True)
            info = {'CFBundleIdentifier':'com.quotaclock.updater-test.'+name, 'CFBundleName':'QuotaClock Update Test', 'CFBundleExecutable':'Probe', 'CFBundlePackageType':'APPL', 'CFBundleVersion':version, 'CFBundleShortVersionString':marketing, 'SUFeedURL':f'http://127.0.0.1:{server.server_port}/{path}', 'SUPublicEDKey':'8xxtAgeWkN9/DA3gYLEPVEOviuXvpNu5jeM2MEd6UaM=', 'SUEnableAutomaticChecks':False, 'SUAutomaticallyUpdate':False, 'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
            (contents/'Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign','--force','--sign','-','--deep',str(app)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            result = subprocess.run([str(contents/'MacOS/Probe')], text=True, capture_output=True, timeout=40)
            assert expected in result.stdout, (name, result.returncode, result.stdout, result.stderr[-1000:])
            print(name+': '+result.stdout.strip(), flush=True)
    finally:
        server.shutdown()
