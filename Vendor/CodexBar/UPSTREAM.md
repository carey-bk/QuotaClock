# CodexBar data engine

Source: https://github.com/steipete/CodexBar
Pinned commit: 6e118bdb5782707bfb0dfd0453d3483e3b216cd0
License: MIT (see LICENSE; bundled source components retain their own license files).

QuotaClock vendors the core, bundled provider plugins, and CLI. Package.swift is reduced to these targets to avoid upstream app/UI dependencies. No runtime download or clone is required. Build with Scripts/build-provider-engine.sh. Core and CLI sources are otherwise kept upstream-compatible; any local patches must be documented here.
