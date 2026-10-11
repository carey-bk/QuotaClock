# CodexBar provider engine integration

Pinned upstream: [steipete/CodexBar](https://github.com/steipete/CodexBar/tree/6e118bdb5782707bfb0dfd0453d3483e3b216cd0), MIT, copyright Peter Steinberger. Vendored in `Vendor/CodexBar`; the reduced package builds the core, built-in plugins and CLI only. No runtime clone, package installation or self-update is performed.

## Counts and verification boundary

Before this change: 6 native provider groups, 9 functioning adapter implementations, 3 explicitly unsupported catalog entries, plus custom Responses API request accounting. Native providers are Codex, Claude, DeepSeek, GLM, Kimi and Bailian. Kimi has three products and Bailian two.

This integration adds all 100 pinned upstream provider IDs as optional `engine-*` sources (100 engine adapters, 109 adapters including native ones). These IDs include tools, aggregators and different products from the same company: they are NOT 100 model companies. Native entries remain available and are not silently migrated. Do not enable native and engine copies expecting their data to be merged.

Validation is offline: registry equality, parser fixtures, isolated configuration permissions, resource loading and compilation. No real account is tested for each entry. An upstream-supported ID is not a claim that a paid account, OAuth flow, browser import or live quota was tested here. Sources that return only text or status without supported numeric fields currently show unavailable instead of fabricated quota. Account-specific errors retain the last known good snapshot through the existing coordinator.

## Runtime

The app embeds `QuotaClockProviderEngine` under Contents/MacOS and the SwiftPM resource bundles under Contents/Resources. Widget and screen saver never link or invoke the engine. The app runs a selected provider only, uses a five-minute minimum automatic refresh interval, allows at most two engine jobs, requests a 20-second engine deadline and enforces a 25-second process deadline plus one-second termination grace. Output is read through a nonblocking pipe and capped at 2 MiB in memory; it is never written to disk. Standard error is discarded to keep credentials and diagnostics out of product snapshots. No shell interpolation or inherited credential environment is used.

The GUI exposes upstream source mode, API token, manual cookie, browser-cookie opt-in, region, endpoint and workspace. Advanced provider-specific options and some login/device flows still require the corresponding tool or editing that provider's private configuration using upstream documentation. There is no automatic login or purchase.

Per-provider configuration lives in `~/Library/Application Support/QuotaClock/ProviderEngine/<id>/config.json`, not the user's CodexBar settings. Secrets use a 0600 file inside a 0700 directory, atomic replacement and the upstream config lock convention. Browser import is off by default. Secrets are not stored in the shared snapshot. Local credential sources can still use their normal Keychain authorization once the user enables that source.

Mapping: primary/secondary/tertiary and named measured windows become remaining percentages; synthetic or unknown windows are omitted; over-quota remaining is clamped to zero. Reported currency balances, spend and dimensionless credits remain separate meters. Only structured numeric progress in details is mapped, never amounts guessed from text. Reset inventory is optional. Email, organization, diagnostics, raw detail strings, redemption IDs and credentials are not published. Claude native layout and Codex multi-account behavior remain unchanged.

## Build

```sh
zsh Scripts/build-provider-engine.sh
xcodegen generate
xcodebuild -project QuotaClock.xcodeproj -scheme QuotaClock -configuration Release -derivedDataPath build.noindex build
swift test
python3 Scripts/sign-release.py
```

The engine build produces Intel and Apple Silicon slices. Release signing signs the helper before the host app. All upstream and dependency license texts ship in `Assets/ProviderEngine-LICENSES.txt` and the source licenses are retained. A build without the engine fails with a clear prerequisite message rather than silently shipping broken entries.

## Pinned registry

Every row below has the same status: upstream implementation included; real-account verification pending.

| ID | Upstream display name |
| --- | --- |
| codex | Codex |
| openai | OpenAI |
| azureopenai | Azure OpenAI |
| claude | Claude |
| clinepass | ClinePass |
| cursor | Cursor |
| opencode | OpenCode |
| opencodego | OpenCode Go |
| alibaba | Alibaba |
| alibabatokenplan | Alibaba Token Plan |
| qwencloud | Qwen Cloud |
| factory | Droid |
| fireworks | Fireworks |
| gemini | Gemini |
| antigravity | Antigravity |
| copilot | Copilot |
| devin | Devin |
| zai | z.ai / GLM |
| minimax | MiniMax |
| manus | Manus |
| kimi | Kimi Code |
| kilo | Kilo |
| kiro | Kiro |
| vertexai | Vertex AI |
| augment | Augment |
| jetbrains | JetBrains AI |
| moonshot | Moonshot / Kimi Open Platform |
| amp | Amp |
| t3chat | T3 Chat |
| langdock | Langdock |
| ollama | Ollama |
| synthetic | Synthetic |
| openrouter | OpenRouter |
| elevenlabs | ElevenLabs |
| warp | Warp |
| windsurf | Windsurf |
| zed | Zed |
| perplexity | Perplexity |
| mimo | Xiaomi MiMo |
| doubao | Doubao |
| sakana | Sakana AI |
| abacus | Abacus AI |
| mistral | Mistral |
| deepseek | DeepSeek |
| deepinfra | DeepInfra |
| codebuff | Codebuff |
| venice | Venice |
| commandcode | Command Code |
| qoder | Qoder |
| stepfun | StepFun |
| bedrock | AWS Bedrock |
| grok | Grok |
| groq | Groq |
| llmproxy | LLM Proxy |
| litellm | LiteLLM |
| bifrost | Bifrost |
| aixy | Aixy |
| deepgram | Deepgram |
| poe | Poe |
| chutes | Chutes |
| neuralwatt | Neuralwatt |
| helmcode | Helmcode |
| clawrouter | ClawRouter |
| longcat | LongCat |
| sub2api | sub2api |
| wayfinder | Wayfinder |
| zenmux | ZenMux |
| aiand | ai& |
| zoommate | ZoomMate |
| xai | xAI |
| xapi | X API |
| notion | Notion AI |
| ibmbob | IBM Bob |
| nous | Nous Portal |
| muse | Muse Code |
| coderabbit | CodeRabbit |
| replicate | Replicate |
| huggingface | Hugging Face |
| raycast | Raycast |
| pi | Pi |
| v0 | v0 |
| typesafe | TypeSafe |
| hyper | Charm Hyper |
| gitkraken | GitKraken AI |
| devpass | DevPass |
| atlascloud | Atlas Cloud |
| vercel | Vercel AI Gateway |
| llmman | llmman |
| xkiro | xKiro |
| museai | Muse (muse.ai) |
| lithosai | LithosAI |
| workbuddy | WorkBuddy |
| tavily | Tavily |
| linkup | Linkup |
| tinyapi | TinyApi |
| exa | Exa |
| cosmic | Cosmic AI |
| aerostack | Aerostack |
| sailresearch | Sail Research |
| sofya | Sofya |


## Validation record (2026-10-11)

- 189 QuotaCore tests passed, including protocol mapping, privacy projection, configuration permissions/preservation, process timeout/cancellation/output bounds and nonzero exit handling.
- Release app build 1.2.0-beta.12 (95) succeeded. The pinned engine has arm64 and x86_64 slices.
- `Scripts/check-provider-engine.sh` passed against the packaged executable using an isolated home/config and disabled Keychain access: all 100 registry IDs matched.
- Developer ID inside-out signing and deep strict verification passed. Build 95 is not notarized or installed; /Applications remains build 93.
- The native configuration view was opened in a dedicated preview app; secure fields, source picker, browser opt-in and expanded region/endpoint/workspace controls were inspected. No credentials were entered or saved and no live usage fetch was performed.
- Known Xcode CoreSimulator plugin mismatch warnings do not affect the macOS build.
