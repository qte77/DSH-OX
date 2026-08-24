# DSH-OX

A local test bench for **DeepSeek Harness** (`dsh`) driven by the **Ox Alpha**
stealth model through **OpenRouter**, with skills ported from
[`claude-code-plugins`](../claude-code-plugins).

## Quickstart

```sh
make setup                    # npm install + create .env
$EDITOR .env                  # add OPENROUTER_API_KEY (https://openrouter.ai/keys)
make skills                   # port CC plugin skills -> .dsh/skills
set -a && . ./.env && set +a  # load the key into your shell

make dump-config              # composed profile tree — works without a key
make run                      # web UI at http://127.0.0.1:3080
make ask JOB="what is this repo?"   # one-shot CLI, prints and exits
make doctor                   # check toolchain, key, skill discovery
```

`make ask` is the fastest smoke test — it needs no browser.

`make setup` has not been run yet in this checkout — the `npm install` was
blocked by a permission classifier during scaffolding. Everything else is in
place.

## Layout

| Path | Role | CC analogue |
|---|---|---|
| `dsh-home/settings.yaml` | Provider + model config (`$DSH_HOME`) | — |
| `.dsh/skills/<name>/SKILL.md` | Project skills, discovery rank 100 | `plugins/*/skills/*/SKILL.md` |
| `AGENTS.md` | Project agent instructions | `CLAUDE.md` |
| `dsh-home/profiles/<name>/` | Profile: `package.json` + `cordis.patch.yml` | `.claude-plugin/marketplace.json` |
| `scripts/port-cc-skills.sh` | CC → DSH skill port | — |

`DSH_HOME` is pinned to `./dsh-home` (via the `Makefile` and `.env`) so this
repo does not write into `~/.dsh`. Unset it to use the DSH default.

## Architecture

### Boot path and wiring

How this repo's inputs reach the model. The launcher composes a profile, the
composed harness resolves skills and the provider, and requests leave through
`ctx.llm`.

```text
  .env                              apps/cli  (launcher)
    OPENROUTER_API_KEY   ------->     dsh --profile NAME
    DSH_HOME=./dsh-home               subcommands: web | plugin
                                      flags: --patch --dump-config
                                                |
                                                v
                    PROFILE   $DSH_HOME/profiles/NAME
                    +-----------------------------------------------+
                    | 1. bundle patches (dsh.profile.bundles order)  |
                    | 2. profile cordis.patch.yml                    |
                    | 3. $DSH_HOME/cordis.patch.yml                  |
                    | 4. --patch overlays                            |
                    +-----------------------------------------------+
                                                |
                                                v
                    COMPOSED HARNESS  (Cordis context)
                    +-----------------------------------------------+
  settings.yaml  -->|  Host                      Client             |
   llm-pi-ai        |    session                   apps/web UI      |
                    |    tools         <------>    127.0.0.1:3080   |
  .dsh/skills/*  -->|    agent-loop                                 |
   64 CC skills     |    skill registry                             |
                    |    ctx.llm                                    |
  AGENTS.md      -->|      |                                        |
                    +------|----------------------------------------+
                           v
                    OpenRouter    openrouter.ai/api/v1
                                  api: openai-completions
                           |
                           v
                    stealth/ox-alpha
                    1M context, anonymous provider
```

### Agent loop

A *step* is one model request plus its tool calls; a *turn* is zero or more
steps. `turn/*`, `step/*`, messages and results are durable session events;
`agent/*` and `tools/*` are live waterfalls you can intercept.

```text
  turn/start
      |
      v
  agent/pre-step  <----------------+     validate / rewrite messages
      |                            |
      v                            |
  step/start                       |
      |                            |
      v                            |
  llm/stream                       |     model request
      |                            |
      v                            |
  assistant/message                | another step
      |                            |
      v                            |
  tools/execute                    |     pre / post hooks
      |                            |
      v                            |
  tool/result                      |
      |                            |
      v                            |
  step/end  -----------------------+
      |
      v
  agent/turn-stopping                    finalize
      |
      v
  turn/end
```

### Module layers

Strict acyclic; each layer depends only on those beneath it.

```text
  +---+------------------------+------------------------------------------+
  | 7 | client & presentation  | UI packages, bundle groups               |
  | 6 | tools & extensions     | tool-bash, tool-fs, tool-workflow,       |
  |   |                        | subagent                                 |
  | 5 | domain                 | goal, filesystem, web, shell, sandbox,   |
  |   |                        | interaction                              |
  | 4 | llm + core             | agent, session, system-prompt, scope,    |
  |   |                        | tools, skill                             |
  | 3 | infrastructure         | storage, subprocess, credentials,        |
  |   |                        | settings, identity                       |
  | 2 | util                   | atomic-write, brand, home-paths,         |
  |   |                        | launch-environment, native-command,      |
  |   |                        | output-retention, timeout                |
  | 1 | invariants             | the only zero-dependency package         |
  +---+------------------------+------------------------------------------+
    ^
    | each layer depends only on the layers below it
```

**Extension seams**: model providers register on `ctx.llm`; tools on `ctx.tools`
(their schema auto-joins the prompt); filesystem and subprocess swap providers
without a fork; subagents are pluggable delegation; interception hooks the
`agent/*` and `tools/*` waterfalls. Every contribution goes through
`ctx.effect()` / `ctx.on()` and returns a disposer.

**Invariant** — *model-visible means logged*: anything reaching the model must be
reconstructable from the session log.

> The boot path above is verified against this repo's files. The agent loop,
> module layers and seams come from upstream `docs/architecture.md`,
> `docs/module-graph.md` and `AGENTS.md`, and are not confirmed against the
> running build.

## The three pieces

### 1. DeepSeek Harness

`dsh` is DeepSeek's open-source agent harness — "everything is a plugin", built
on [Cordis](https://github.com/cordiverse/cordis). Installed version here:
`@deepseek-ai/dsh@0.1.1-rc.2`.

It has both a web UI and a CLI; the launcher parses only its own flags and
forwards the rest to the booted profile's app.

```sh
dsh web                              # alias of --profile web -> 127.0.0.1:3080
dsh web --no-open                    # same, no browser
dsh web --port 8080                  # --port belongs to the web app
dsh --profile headless "run tests"   # one-shot: fresh persisted session, print, exit
dsh --profile <name>                 # boot any profile in $DSH_HOME/profiles
dsh plugin --profile web add <pkg>   # manage profile plugins (forwards to pnpm)
```

Launcher flags: `--profile <name>`, `--patch <path>` (repeatable),
`--dump-config`, `--dump-default-config`, `-V/--version`. `--dump-config` prints
the composed profile tree and exits — useful before you have a key.

Only two apps ship: `apps/cli` and `apps/web`. The upstream CLI README shows a
`--profile tui --resume <id>` example, but no TUI app exists in the repo — treat
it as illustrative of a custom profile, not something you can boot today.

**Skill discovery roots**, highest priority first:

| Rank | Source | Root |
|---|---|---|
| 100 | `project-dsh` | `<projectRoot>/.dsh/skills` |
| 200 | `project-agents` | `<projectRoot>/.agents/skills` |
| 300 | `custom` | `Config.customSkillDirs` |
| 400 | `user-dsh` | `<dshHome>/skills` |
| 500 | `user-agents` | `<agentsHome>/skills` |
| 600 | `bundled` | `Config.bundledSkillDir` |

Project root is the nearest ancestor containing `.git`.

### 2. Ox Alpha via OpenRouter

Ox Alpha is a **stealth model**: frontier-class, released anonymously so its
developer can gather feedback pre-launch. On OpenRouter it is `stealth/ox-alpha`
— 1,048,576-token context, up to 131,072 completion tokens, free during the
preview.

Configured in `dsh-home/settings.yaml`:

```yaml
llm-pi-ai:
  providers:
    openrouter:
      apiKeyEnv: OPENROUTER_API_KEY
      api: openai-completions
      baseURL: https://openrouter.ai/api/v1
      models:
        - id: stealth/ox-alpha
```

If DSH rejects that file, add the provider through the UI instead —
**Settings → Models → "Add a custom provider"** — with the same four values.

### 3. Ported Claude Code skills

Both harnesses use `<name>/SKILL.md` with YAML frontmatter carrying `name` and
`description`, so skills port almost unchanged. `make skills` copies **64
skills** from 22 CC plugins into `.dsh/skills/` and retargets the CC-only
`compatibility:` line.

DSH frontmatter also recognises `disable-model-invocation` and `user-invocable`
(both default `true`).

## Before you send a real repo through this

- **Ox Alpha's provider is anonymous.** OpenRouter states prompts and
  completions "are retained by the provider and are not used for training", but
  nobody has confirmed who the provider is — attribution has been guessed at
  both Z.ai and Microsoft MAI, with no official claim. An agent harness reads
  your source tree. Treat this as an experiment on throwaway or public code, not
  on anything confidential.
- **It runs under OpenRouter's separate Stealth Model Terms**, not standard
  provider terms.
- **The free window is time-boxed.** Ox Alpha launched 2026-08-20 with a preview
  reported as roughly one week. Expect it to change price or disappear; the
  commented fallbacks in `settings.yaml` are there for that.
- **`dsh` is `0.1.1-rc.2`** and its README warns of compatibility-breaking
  changes.
- **`dsh-home/settings.yaml` is written from the docs, not verified against the
  running build** — the Web UI path above is the fallback.

## Avoid `oxalpha.io`

The page `oxalpha.io/blog/ox-alpha-openrouter-guide.html` is titled as an
OpenRouter guide but routes readers to a third-party reseller, `tokenra.io`,
telling them to register there and generate an API key against
`https://tokenra.io/v1/chat/completions`. That is not OpenRouter and not an
official Ox Alpha channel. The model itself is real; use
[openrouter.ai/stealth/ox-alpha](https://openrouter.ai/stealth/ox-alpha)
directly.

## Profiles, and how plugins are actually installed

`dsh` boots **profiles** — ordered stacks of plugin-bundle patch layers under
your own overrides. A profile lives in `$DSH_HOME/profiles/<name>/` and holds:

- `package.json` — its dependencies plus a `dsh.profile.bundles` manifest
- `cordis.patch.yml` — the user patch layer

Composition order, first to last:

1. each bundle's patch, in `dsh.profile.bundles` order
2. the profile's `cordis.patch.yml`
3. `$DSH_HOME/cordis.patch.yml`
4. any `--patch <path>` overlays (repeatable)

Bundles resolve from the dsh installation first, then the profile's
`node_modules`. `web` and `headless` auto-initialize from shipped templates;
any other profile must be created via `dsh plugin`.

**Plugin install is pnpm, forwarded through the CLI** — this is the real
analogue to a CC marketplace:

```sh
dsh plugin --profile web add <pkg>       # args forwarded verbatim to pnpm
dsh plugin --profile web remove <pkg>
dsh plugin --profile web why <pkg>
make plugin-add PKG=<pkg> PROFILE=web    # same thing
```

Individual plugin config still uses `cordis.yml`-style entries — a package name
mapped to a `config:` block, with omission disabling the plugin:

```yaml
'@deepseek-ai/dsh-host-webserver':
  config:
    host: '127.0.0.1'
    port: 8080
```

Nothing is committed here: a wrong patch layer breaks startup and DSH writes its
own defaults. Inspect what you actually get with `make dump-config` before
overriding anything.

## The `dsh-plugin` ecosystem

The [`dsh-plugin` topic](https://github.com/topics/dsh-plugin) is the discovery
mechanism DSH's README points at. Genuinely DSH-related entries include
`nexu-io/open-design`, `esengine/DeepSeek-Reasonix`,
`anywhere-labs/deepseek-harness-desktop`, `volcengine/OpenViking` and
`tt-a1i/archify`. Note the topic is self-applied and unmoderated — several
high-star repos carrying it (`amruthpillai/reactive-resume`, `Molunerfinn/PicGo`,
`nocobase/nocobase`) are unrelated projects. Star count is not a signal of DSH
compatibility.
