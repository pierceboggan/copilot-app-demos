# octo-internal marketplace

A working private plugin marketplace, used by the `extraKnownMarketplaces` and `enabledPlugins` demo.

It contains one plugin, `octo-standards`, which ships a skill and a slash command. Nothing here is fictional in the sense that matters: the CLI registers it, installs from it, and loads both components.

## Try it

```bash
export COPILOT_HOME=$(mktemp -d)          # keep your real config out of this
copilot plugin marketplace add "$PWD"
copilot plugin marketplace browse octo-internal
copilot plugin install octo-standards@octo-internal
copilot skill list
```

You should see `secure-defaults` and `octo-checklist` under plugin skills.

A directory-sourced marketplace loads live. Editing a file here takes effect in the next session with no reinstall.

## Distributing it through managed settings

```json
{
  "extraKnownMarketplaces": {
    "octo-internal": {
      "source": {
        "source": "github",
        "repo": "pierceboggan/copilot-app-demos",
        "ref": "main",
        "path": "enterprise-managed-settings/marketplace"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "octo-standards@octo-internal": true
  }
}
```

The `path` points at the directory holding `.github/plugin/marketplace.json`, not at the manifest itself.

Two things to know before doing this for real. The marketplace key in `extraKnownMarketplaces` has to match the `name` inside `marketplace.json`, because that name is the registration key and cannot be aliased locally. And a force-installed plugin still needs the user to have read access to wherever it is hosted, so a private repository means anyone without access simply fails to install it.

Add `strictKnownMarketplaces` to make this the *only* source anyone can install from:

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "pierceboggan/copilot-app-demos" }
  ]
}
```

An empty array there locks plugin installation down completely.

## Layout

```
.github/plugin/marketplace.json     catalog: name, owner, plugin list
plugins/
  octo-standards/
    plugin.json                     Agent Plugins 1.0 manifest
    skills/
      secure-defaults/SKILL.md      portable skill
    com.github.copilot/
      commands/octo-checklist.md    Copilot-specific slash command
```

`metadata.pluginRoot` is `plugins`, and each entry's `source` resolves *relative to that root*. So the entry reads `./octo-standards`, not `./plugins/octo-standards`. Writing the full path produces `plugins/plugins/octo-standards` and an install failure that names a directory you never wrote down.

Skills live in `skills/<name>/SKILL.md` and MCP servers in `mcp.json` at the plugin root. Those two locations are fixed by the Agent Plugins 1.0 spec and cannot be redirected from `plugin.json`. Anything Copilot-specific, including agents, commands, rules, hooks, and LSP servers, goes under a `com.github.copilot/` directory, which other clients ignore.

## Reference

* [Plugin standards](https://docs.github.com/copilot/concepts/enterprise/plugin-standards)
* [CLI plugin reference](https://docs.github.com/copilot/reference/copilot-cli-reference/cli-plugin-reference)
* [Agent Plugins 1.0 specification](https://github.com/agentplugins/agent-plugins-spec/blob/main/spec/1.0.0.md)
