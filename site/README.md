# QuotaClock website

Dependency-free static HTML, CSS and JavaScript. The Screen Saver is reconstructed from the native app; the MacBook hardware and clipping geometry reuse the LiveCopilot website asset. All public account data is fictional.

## Build and preview

From the repository root:

```sh
python3 Scripts/build-site.py --production
python3 Scripts/check-site.py
node --check site/app.js
python3 -m http.server 18746 --bind 127.0.0.1 --directory _site
```

Open `http://127.0.0.1:18746/`. Generated `_site/` is ignored by Git. `site/dist/` is the original simple page retained for reference; it is no longer deployed.

The Pages workflow builds, validates and deploys `_site/` on changes to the website, build scripts or `project.yml` on `main`. No package installation is required. `site/config.json` stores the verified release download, release version and CPU architectures. Minimum macOS comes from `project.yml`; a local app version alone does not create a public download.

`SITE_REPOSITORY`, `SITE_URL` and `SITE_RELEASE_URL` override the corresponding configuration fields. For a custom domain, update the Pages domain and `site_url`; the workflow takes the canonical base URL from `actions/configure-pages`. Relative resources and the generated 404 base support both a project subpath and a domain root.

## Editing

- `sections/01-…12-*.html`: ordered homepage sections.
- `components/saver.html`: shared screen saver preview.
- `template.html`, `styles.css`, `app.js`: page shell, responsive design and isolated interactive demos.
- `privacy.html`, `404.html`: supporting pages.
- `og.html`: fixed 1200 × 630 composition used to capture `assets/og-image.png`. Refresh the PNG after changing social-preview content.
- `assets/`: app icons, provider marks, hardware exports and their provenance/license notices. Never include private source PSDs, Apple font files, personal account screenshots or credentials.

## Acceptance

The initial implementation followed Foundation → Hero / Screen Saver → Product Surfaces → Codex Switching → Settings / Providers / GitHub → Polish, with desktop and mobile browser checks at each gate. Local screenshots and detailed observations live in ignored `Evidence/website/`.

Final checks cover 320–1440px layouts, tablet hardware, mobile frame removal, synchronized Alpha/Beta/Gamma switching, menu Escape, settings keyboard tabs, skip-link focus, reduced motion, lazy images, API-failure fallback, metadata and relative assets. The static validator runs in CI. Optional GitHub stars never gate rendering or download links. There are no analytics, third-party fonts, web frameworks or WebGL dependencies.

After deployment, verify the actual Pages URL on desktop and mobile, switch Gamma to 100%, check a Settings tab, follow Privacy and the 404 return link, and confirm the current DMG destination. CI success and local screenshots alone do not verify the public page.
