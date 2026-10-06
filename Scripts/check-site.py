#!/usr/bin/env python3
"""Validate the deployable artifact: links, accessibility basics, metadata, privacy and budget."""
import argparse, json, os, re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--directory',type=Path,default=root/'_site')
args=parser.parse_args()
errors=[]
class Page(HTMLParser):
    def __init__(self,text):
        super().__init__(convert_charrefs=True)
        self.ids=[];self.links=[];self.images=[];self.headings=[];self.meta={};self.text=[];self.canonical=None;self.base=None
        self.feed(text)
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag in ('a','script','link','img','source'):
            for key in ('href','src','srcset'):
                if a.get(key):self.links.append(a[key].split()[0])
        if tag=='img':self.images.append(a)
        if tag in ('h1','h2','h3'):self.headings.append(tag)
        if tag=='meta':self.meta[a.get('name',a.get('property',''))]=a.get('content')
        if tag=='link' and a.get('rel')=='canonical':self.canonical=a.get('href')
        if tag=='base':self.base=a.get('href')
    def handle_data(self,text):self.text.append(text)

pages={p.name:Page(p.read_text()) for p in args.directory.glob('*.html')}
for name,page in pages.items():
    text=(args.directory/name).read_text()
    if re.search(r'@@[A-Z_]+@@',text):errors.append(f'{name}: unresolved template')
    if len(page.ids)!=len(set(page.ids)):errors.append(f'{name}: duplicate IDs')
    if page.headings.count('h1')!=1:errors.append(f'{name}: requires one h1')
    if any('alt' not in img for img in page.images):errors.append(f'{name}: missing image alt')
    if re.search(r'\b(?:Carey|Alice|Hanz)\b',' '.join(page.text),re.I):errors.append(f'{name}: personal name in public text')
    for raw in page.links:
        url=urlparse(raw)
        if url.scheme or url.netloc:continue
        path=unquote(url.path)
        if path.startswith('/'):
            errors.append(f'{name}: root-relative resource {raw}');continue
        target=args.directory/(path or name)
        if path in ('.','./'):target=args.directory/'index.html'
        if not target.exists():errors.append(f'{name}: missing {raw}')
        if url.fragment and (not path or target.name in pages):
            destination=page if not path else pages[target.name]
            if url.fragment not in destination.ids:errors.append(f'{name}: missing anchor {raw}')
index=pages['index.html']
config=json.loads((root/'site/config.json').read_text())
site_url=(os.environ.get('SITE_URL') or config['site_url']).rstrip('/')+'/'
release_url=os.environ.get('SITE_RELEASE_URL') or config['release_url']
if index.canonical!=site_url:errors.append('Canonical URL mismatch')
for key in ('description','og:title','og:description','og:image','og:image:alt','twitter:card'):
    if not index.meta.get(key):errors.append(f'Missing {key}')
expected=['overview','screen-saver','menu-bar','accounts','switching','providers','open-source','download']
positions=[index.ids.index(i) for i in expected]
if positions!=sorted(positions):errors.append('Section order incorrect')
if release_url not in index.links:errors.append('Missing verified download')
if pages['404.html'].base!=urlparse(site_url).path:errors.append('404 base path mismatch')
for file in ('robots.txt','sitemap.xml','.nojekyll','assets/og-image.png','assets/native/menu-mask.svg'):
    if not (args.directory/file).exists():errors.append(f'Missing {file}')
for name,budget in [('app.js',30000),('styles.css',60000),('index.html',65000),('assets/macbook.webp',160000)]:
    size=(args.directory/name).stat().st_size
    if size>budget:errors.append(f'{name}: exceeds {budget} byte budget ({size})')
# Some native states are selected dynamically by JavaScript, outside HTML links.
native_names=[f'{kind}-{account}' for kind in ('saver-landscape','saver-portrait','widget','menu','chooser') for account in ('alpha','beta')]
native_names=[name+'-idle' if name.startswith('menu-') else name for name in native_names]
native_names += ['settings-default-'+section for section in ('general','services','menubar','saver')]
native_names += ['widget-large-alpha','widget-large-beta','widget-medium-claude','widget-small-deepseek','status-alpha','status-beta']
native_bytes=0
for name in native_names:
    path=args.directory/'assets/native'/f'{name}.webp'
    if not path.exists():errors.append(f'Missing native UI state {path.name}')
    else:
        data=path.read_bytes();native_bytes+=len(data)
        if data[:4]!=b'RIFF' or data[8:12]!=b'WEBP':errors.append(f'Invalid native WebP {path.name}')
if native_bytes>750000:errors.append(f'Native screenshots exceed 750000 byte budget ({native_bytes})')
for path in args.directory.rglob('*'):
    if path.suffix.lower() in {'.woff','.woff2','.ttf','.otf','.dmg','.env'}:errors.append(f'Unexpected public artifact {path.name}')
if errors:raise SystemExit('\n'.join(errors))
print(f'PASS: {len(pages)} HTML pages; local links/anchors; semantic headings; metadata; demo-name privacy; base path; static assets and transfer budgets.')
print(json.dumps({name:(args.directory/name).stat().st_size for name in ('index.html','styles.css','app.js','assets/macbook.webp','assets/og-image.png')}))
