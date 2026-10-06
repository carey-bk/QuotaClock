#!/usr/bin/env python3
"""Sign an app-only Sparkle ZIP and emit the GitHub Release appcast. Does not publish."""
import argparse
from email.utils import formatdate
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=ROOT/'build.noindex/Build/Products/Release/QuotaClock.app')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
info = plistlib.loads((args.app/'Contents/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not str(build).isdigit():
    raise SystemExit('Expected a stable version and numeric build')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
args.output.mkdir(parents=True, exist_ok=True)
archive = args.output/f'QuotaClock-{version}-{build}.zip'
if archive.exists():
    raise SystemExit(f'Refusing to overwrite {archive}')
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(args.app), str(archive)], check=True)
signer = ROOT/'build.noindex/sparkle-tools/bin/sign_update'
signature = subprocess.check_output([str(signer), '--account', 'com.quotaclock.app', str(archive)], text=True).strip()
# Parse only the documented XML attributes from Sparkle's output.
enclosure = ET.fromstring('<enclosure xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" '+signature+'/>')
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
assert enclosure.get('{'+namespace+'}edSignature'), 'Missing Sparkle signature'
assert int(enclosure.get('length')) == archive.stat().st_size
public_key = subprocess.check_output([str(signer.parent/'generate_keys'), '--account', 'com.quotaclock.app', '-p'], text=True).strip()
assert public_key == info['SUPublicEDKey'], 'Signing key does not match the shipped app'
subprocess.run([str(signer), '--account', 'com.quotaclock.app', '--verify', str(archive), enclosure.get('{'+namespace+'}edSignature')], check=True)
ET.register_namespace('sparkle', namespace)
rss = ET.Element('rss', {'version':'2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'QuotaClock Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'QuotaClock {version}'
ET.SubElement(item, 'pubDate').text = formatdate(usegmt=True)
for key, value in [('version', str(build)), ('shortVersionString', version), ('minimumSystemVersion', '14.0')]:
    ET.SubElement(item, '{'+namespace+'}'+key).text = value
ET.SubElement(item, 'description').text = 'Built-in signed updates and reduced Codex polling bandwidth. Screen saver updates are available from About.'
enclosure.set('url', f'https://github.com/carey-bk/QuotaClock/releases/download/v{version}/{archive.name}')
enclosure.set('type', 'application/octet-stream')
item.append(enclosure)
ET.indent(rss)
ET.ElementTree(rss).write(args.output/'appcast.xml', encoding='utf-8', xml_declaration=True)
print(archive)
print(args.output/'appcast.xml')
