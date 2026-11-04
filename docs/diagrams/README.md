# Caption application diagrams

architecture.mmd maps current caption-only components. caption-policy.mmd shows commitment and direct publication decisions. Keep editable Mermaid and SVG/PNG exports synchronized. See the [architecture](../../ARCHITECTURE.md) and [policy](../CAPTION_POLICY.md).

## Regeneration

Use Mermaid CLI 12.0.0, Node 22.13+, and an installed Chrome/Chromium. Prefer arm64 Node on Apple Silicon. From the repository root:

```sh
export PUPPETEER_SKIP_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for diagram in architecture caption-policy; do
  npx --yes @mermaid-js/mermaid-cli@12.0.0 -i "docs/diagrams/$diagram.mmd" -c docs/diagrams/mermaid.config.json -o "docs/diagrams/$diagram.svg" -b white --size 2000 --no-font-embed
  npx --yes @mermaid-js/mermaid-cli@12.0.0 -i "docs/diagrams/$diagram.mmd" -c docs/diagrams/mermaid.config.json -o "docs/diagrams/$diagram.png" -b white --size 2000 --no-font-embed
done
```

The pinned CLI can be reused from the npm cache. Rendering is authoring tooling, not an app dependency; no JavaScript packages are added to the Swift project. htmlLabels is disabled for portable SVG text. Inspect PNGs for clipping/overlaps and check local links. Runtime changes require app checks; documentation-only changes do not.
