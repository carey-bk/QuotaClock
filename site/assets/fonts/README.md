# Chinese website fonts

Self-hosted Source Han Serif CN SemiBold (600) and Source Han Sans CN Regular (400), from Adobe's official `release/SubsetOTF/CN` distributions:

- https://github.com/adobe-fonts/source-han-serif
- https://github.com/adobe-fonts/source-han-sans

Licensed under the accompanying SIL Open Font License files. WOFF2 subsets contain the Chinese locale catalog and printable ASCII. Regenerate when adding Chinese copy using fontTools `pyftsubset` with `--text-file` containing all `zh-CN` catalog values and printable ASCII, `--flavor=woff2`. No third-party font requests are made by visitors.
