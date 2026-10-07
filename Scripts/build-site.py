#!/usr/bin/env python3
"""Dependency-free static build. Never infer a public release from a local app version."""
import argparse, hashlib, html, json, os, re, shutil
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'site'
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / '_site')
parser.add_argument('--production', action='store_true')
args = parser.parse_args()
config = json.loads((SOURCE / 'config.json').read_text())
config['repository'] = os.environ.get('SITE_REPOSITORY') or config['repository']
config['site_url'] = os.environ.get('SITE_URL') or config['site_url']
config['release_url'] = os.environ.get('SITE_RELEASE_URL') or config['release_url']
repo = config['repository']
if repo and not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
    raise SystemExit('repository must be owner/name')
for key in ('site_url', 'release_url'):
    if config[key] and (urlparse(config[key]).scheme != 'https' or not urlparse(config[key]).netloc):
        raise SystemExit(f'{key} must be an absolute HTTPS URL')
if args.production and not all(config.get(key) for key in ('repository','site_url','release_url','release_version','architectures')):
    raise SystemExit('Production requires a verified repository, site_url, release_url, release_version and architectures in site/config.json.')
project = (ROOT / 'project.yml').read_text()
version = re.search(r'MARKETING_VERSION:\s*([\d.]+)', project)[1]
macos = re.search(r"MACOSX_DEPLOYMENT_TARGET:\s*['\"]?([\d.]+)", project)[1]
esc = lambda text: html.escape(str(text), quote=True)
repository_url = f'https://github.com/{repo}' if repo else None

def action(label, url, style=''):
    classes = f'button {style}'.strip()
    if url:
        return f'<a class="{classes}" href="{esc(url)}">{label}</a>'
    return f'<button class="{classes}" data-release-info>{label}</button>'

parts = sorted((SOURCE/'sections').glob('*.html'))
sections = '\n'.join(part.read_text() for part in parts)
footer = '' if not repository_url else ''.join(f'<a href="{repository_url}{path}">{label}</a>' for label,path in [('GitHub',''),('Releases','/releases'),('Changelog','/releases')])
canonical = ''
if config['site_url']:
    url=config['site_url'].rstrip('/')+'/'
    canonical=f'<link rel="canonical" href="{esc(url)}"><meta property="og:url" content="{esc(url)}">'
else:
    canonical='<meta name="robots" content="noindex,nofollow">'
values = {
 'SECTIONS': sections, 'MIN_MACOS': macos,
 'CSS_HASH':hashlib.sha256((SOURCE/'styles.css').read_bytes()).hexdigest()[:10],
 'LOCALE_HASH':hashlib.sha256((SOURCE/'locales.json').read_bytes()).hexdigest()[:10],
 'I18N_HASH':hashlib.sha256((SOURCE/'i18n.js').read_bytes()).hexdigest()[:10],
 'JS_HASH':hashlib.sha256((SOURCE/'app.js').read_bytes()).hexdigest()[:10],
 'SAVER': (SOURCE/'components/saver.html').read_text(),
 'VERSION': esc(config['release_version'] or version),
 'VERSION_LABEL': 'Current version' if config['release_version'] else 'In development',
 'ARCHITECTURES': esc(config['architectures'] or ''),
 'CANONICAL': canonical,
 'DOWNLOAD_CTA': action('Download for macOS',config['release_url'],'accent'),
 'DOWNLOAD_NAV': action('Download',config['release_url'],'small'),
 'GITHUB_CTA': action('GitHub',repository_url,'secondary'),
 'GITHUB_NAV': f'<a href="{repository_url}">GitHub</a>' if repository_url else '<button class="plain-link" data-release-info>GitHub</button>',
 'FOOTER_LINKS':footer,
 'PRODUCT_NAV': '<a href="#menu-bar">Menu Bar</a><a href="#accounts">Accounts</a>' if 'id="menu-bar"' in sections else '',
 'REPOSITORY_URL': esc(repository_url or '#open-source'),
 'REPOSITORY':esc(repo or ''),
 'BASE_PATH':esc((urlparse(config['site_url']).path.rstrip('/')+'/' if config['site_url'] else '/')),
 'OG_META': (f'<meta property="og:image" content="{esc(config["site_url"].rstrip("/"))}/assets/og-image.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="QuotaClock screen saver with fictional AI accounts"><meta name="twitter:card" content="summary_large_image">' if config['site_url'] else ''),
}

def render(text):
    for _ in range(3):
        text=re.sub(r'@@([A-Z_]+)@@',lambda m:values.get(m[1],m[0]),text)
    if re.search(r'@@[A-Z_]+@@',text): raise SystemExit('Unresolved template token')
    return text

args.output.mkdir(parents=True,exist_ok=True)
for name in ('styles.css','app.js','i18n.js'):
    shutil.copyfile(SOURCE/name,args.output/name)
(args.output/'locales.js').write_text('window.QuotaClockLocales='+json.dumps(json.loads((SOURCE/'locales.json').read_text()),ensure_ascii=False)+';\n')
shutil.copytree(SOURCE/'assets',args.output/'assets',dirs_exist_ok=True)
(args.output/'index.html').write_text(render((SOURCE/'template.html').read_text()))
for page in ('privacy','404','og'):
    source=SOURCE/f'{page}.html'
    if source.exists(): (args.output/f'{page}.html').write_text(render(source.read_text()))
(args.output/'.nojekyll').touch()
if config['site_url']:
    url=config['site_url'].rstrip('/')+'/'
    (args.output/'robots.txt').write_text(f'User-agent: *\nAllow: /\nSitemap: {url}sitemap.xml\n')
    (args.output/'sitemap.xml').write_text(f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>{esc(url)}</loc></url><url><loc>{esc(url)}privacy.html</loc></url></urlset>')
print(f'Built {args.output}: {len(parts)} section files, app {version}, macOS {macos}+.')
