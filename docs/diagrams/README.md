# Architecture diagram

`architecture.mmd` is the editable source of truth. `architecture.svg` is embedded in the project README and ARCHITECTURE.md; `architecture.png` provides a raster preview for viewers that cannot display SVG. Keep all three in sync when the architecture changes.

The diagram maps the components currently implemented in the repository. It distinguishes the application process from native macOS frameworks, preferences storage, and the separate local Ollama process. Each provider box pairs its application protocol with its current adapter. The gray section contains planned embedded inference and model management. AppContainer is identified as the composition root; arrow labels distinguish observation, API calls, and policy dependencies. The runtime sequence lives in [ARCHITECTURE.md](../../ARCHITECTURE.md#data-flow).

## Regenerate

Rendering is a documentation-authoring step, not an application dependency. The exports were generated with Mermaid CLI 12.0.0 and the existing local Chrome installation. That CLI requires Node.js 22.13 or newer; on Apple Silicon use an arm64 Node installation to avoid Chrome launch problems under Rosetta. No npm manifest or JavaScript dependency is added to the Swift application.

Run from the repository root:

```sh
export PUPPETEER_SKIP_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

npx --yes @mermaid-js/mermaid-cli@12.0.0 \
  -i docs/diagrams/architecture.mmd \
  -c docs/diagrams/mermaid.config.json \
  -o docs/diagrams/architecture.svg -b white --size 2000 --no-font-embed

npx --yes @mermaid-js/mermaid-cli@12.0.0 \
  -i docs/diagrams/architecture.mmd \
  -c docs/diagrams/mermaid.config.json \
  -o docs/diagrams/architecture.png -b white --size 2000 -s 2 --no-font-embed
```

On another system, set the executable path to a compatible installed Chromium/Chrome binary. The first `npx` invocation downloads the pinned rendering tool into the npm cache. `htmlLabels` is disabled so the SVG contains portable SVG text rather than HTML foreign objects.

After rendering, inspect the PNG for clipped labels and overlapping edges, and verify that component names and connections still match the implementation. Documentation-only changes do not require rerunning app tests or rebuilding the app.
