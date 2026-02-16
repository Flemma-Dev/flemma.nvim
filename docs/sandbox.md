# Sandboxing

Flemma can sandbox tool execution so that shell commands run inside a constrained filesystem. The sandbox mounts the entire rootfs read-only and grants write access only to an explicit allowlist of paths. A misbehaving model cannot `rm -rf /`, overwrite dotfiles, or write outside your project directory.

> [!IMPORTANT]
> **The sandbox is damage control, not prevention.** It limits the blast radius when something goes wrong – the model can still do anything within its writable paths, including reading sensitive files and sending them over the network. It will not stop a bash tool from `cat`-ing your `.env` and `curl`-ing it to a remote server. The sandbox protects against the common accidents (a hallucinated `rm`, a stray write to `/etc`), not against a determined adversary. Always review the tools you are using and understand their potential risks, even in a sandboxed environment.

Sandboxing is enabled by default. On platforms where no backend is available (e.g., macOS), Flemma silently falls back to unsandboxed execution – no configuration changes needed.

For a quick overview of the tool system and approval workflow, see [Tool Calling](../README.md#tool-calling) in the README.

---

## How it works

Flemma's sandbox has two layers:

1. **Policy layer** (`sandbox/init.lua`) – defines _what_ is allowed: which paths are writable, whether network access is permitted, whether the agent can use `sudo`. Tools call this layer's API; they never talk to backends directly.
2. **Backend layer** (e.g., `sandbox/backends/bwrap.lua`) – translates the policy into enforcement. The first backend is [Bubblewrap](https://github.com/containers/bubblewrap) (Linux). The abstraction boundary makes it straightforward to add backends for other platforms without changing the policy schema or tool integration.

When a tool executes a shell command, the sandbox wraps it:

```
vim.fn.jobstart(cmd)            -- without sandbox
vim.fn.jobstart(bwrap ... cmd)  -- with sandbox
```

If sandboxing is disabled or no backend is available, the command runs unchanged.

---

## Quick start

Sandboxing is on by default with sensible settings. If you are on Linux with `bwrap` installed, it works out of the box:

```bash
# Debian/Ubuntu
sudo apt install bubblewrap

# Fedora
sudo dnf install bubblewrap

# Arch
sudo pacman -S bubblewrap
```

No configuration changes are needed. Flemma auto-detects the backend and applies the default policy.

To verify, open a `.chat` buffer and run:

```vim
:Flemma sandbox:status
```

---

## Configuration

The sandbox is a top-level config key, sibling to `tools`, `parameters`, `provider`, etc.

```lua
require("flemma").setup({
  sandbox = {
    enabled = true,               -- Master switch (default: true)
    backend = "auto",             -- "auto" | "required" | explicit name (default: "auto")
    policy = {
      rw_paths = {                -- Read-write paths (all others are read-only)
        "$CWD",                   --   Vim global working directory (from :cd)
        "$FLEMMA_BUFFER_PATH",    --   Directory of the current .chat file
        "/tmp",                   --   System temp directory
      },
      network = true,             -- Allow network access (default: true)
      allow_privileged = false,   -- Allow sudo/capabilities (default: false)
    },
    backends = {
      bwrap = {
        path = "bwrap",           -- Path to bubblewrap binary
        extra_args = {},          -- Additional bwrap arguments
      },
    },
  },
})
```

See [docs/configuration.md](configuration.md) for the full option reference.

### Backend modes

The `backend` field controls how Flemma selects a sandbox backend:

| Value        | Behaviour                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------ |
| `"auto"`     | Iterate registered backends by priority, pick the first that works. Log quietly if none found.   |
| `"required"` | Same detection logic, but warn visibly on first `.chat` buffer entry if no backend is available. |
| explicit     | Use the named backend directly. Error if it is unavailable.                                      |

The default is `"auto"` – Flemma silently degrades to unsandboxed execution on platforms without a compatible backend. Use `"required"` if you want to be notified when sandboxing is not active:

```lua
sandbox = {
  backend = "required",
}
```

### Policy options

| Key                | Default                                     | Effect                                                                        |
| ------------------ | ------------------------------------------- | ----------------------------------------------------------------------------- |
| `rw_paths`         | `{ "$CWD", "$FLEMMA_BUFFER_PATH", "/tmp" }` | Paths with read-write access. Everything else is read-only.                   |
| `network`          | `true`                                      | Allow network access inside the sandbox.                                      |
| `allow_privileged` | `false`                                     | Allow `sudo` and capabilities. When `false`, user namespaces drop privileges. |

### Path variables

Paths in `rw_paths` support two variables that are expanded at execution time:

| Variable              | Expansion                                    | Source                                |
| --------------------- | -------------------------------------------- | ------------------------------------- |
| `$CWD`                | Vim's global working directory               | `vim.fn.getcwd()` (set by `:cd`)      |
| `$FLEMMA_BUFFER_PATH` | Directory containing the current buffer file | `vim.fn.fnamemodify(bufname, ":p:h")` |

After expansion, all paths are normalized to absolute paths with symlinks resolved. Duplicate paths are deduplicated. Unknown `$VARIABLES` produce a warning and are skipped.

---

## Per-buffer overrides

Override sandbox settings per-buffer using `flemma.opt.sandbox` in Lua frontmatter:

````lua
```lua
-- Enable sandboxing for this buffer
flemma.opt.sandbox = true

-- Disable sandboxing for this buffer
flemma.opt.sandbox = false

-- Fine-grained override
flemma.opt.sandbox = {
  enabled = true,
  policy = {
    rw_paths = { "$CWD", "/data/experiments" },
    network = false,
  },
}
```
````

The boolean shorthand (`flemma.opt.sandbox = true`) expands to `{ enabled = true }`.

### Precedence order (highest wins)

1. **Runtime override** (`:Flemma sandbox:enable/disable`) – session-level, cleared on restart
2. **Per-buffer frontmatter** (`flemma.opt.sandbox`)
3. **Global config** (`require("flemma").setup({ sandbox = { ... } })`)

---

## Runtime commands

Toggle sandboxing at runtime without changing your config:

| Command                   | Effect                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `:Flemma sandbox:enable`  | Enable sandboxing for the current session (validates backend) |
| `:Flemma sandbox:disable` | Disable sandboxing for the current session                    |
| `:Flemma sandbox:status`  | Show effective state, backend, and availability               |

The runtime override is session-level and applies to all buffers. Fine-grained per-buffer control stays in frontmatter.

---

## Examples

### Minimal (defaults)

The defaults give you read-only `/`, read-write access to your working directory and `.chat` file directory, plus `/tmp`. Network is allowed. No `sudo`.

```lua
require("flemma").setup({})  -- sandbox is on by default
```

### Strict isolation

No `/tmp`, no network, only the project directory is writable:

```lua
require("flemma").setup({
  sandbox = {
    policy = {
      rw_paths = { "$CWD" },
      network = false,
    },
  },
})
```

### Private `/tmp`

Instead of sharing the host's `/tmp`, mount a private tmpfs that is discarded when the sandbox exits:

```lua
require("flemma").setup({
  sandbox = {
    policy = {
      rw_paths = { "$CWD", "$FLEMMA_BUFFER_PATH" },  -- remove /tmp from rw_paths
    },
    backends = {
      bwrap = {
        extra_args = { "--tmpfs", "/tmp" },  -- private tmpfs inside sandbox
      },
    },
  },
})
```

### Disable sandboxing

```lua
require("flemma").setup({
  sandbox = { enabled = false },
})
```

---

## Custom backends

The sandbox uses a registry pattern identical to [approval resolvers](tools.md#approval-resolvers). Each backend provides two functions: `available()` (can this backend run?) and `wrap()` (translate the policy into a command wrapper).

### Registering a backend

```lua
local sandbox = require("flemma.sandbox")

sandbox.register("my_backend", {
  available = function(backend_config)
    -- Return true if the backend can run, or false + error string
    if vim.fn.executable("my-sandbox-tool") ~= 1 then
      return false, "my-sandbox-tool not found"
    end
    return true, nil
  end,
  wrap = function(policy, backend_config, inner_cmd)
    -- policy.rw_paths contains only absolute, deduplicated paths (no variables)
    -- Return a flat string[] suitable for vim.fn.jobstart()
    local args = { "my-sandbox-tool" }
    for _, path in ipairs(policy.rw_paths or {}) do
      vim.list_extend(args, { "--allow-write", path })
    end
    vim.list_extend(args, inner_cmd)
    return args, nil
  end,
  priority = 80,              -- Higher = preferred during auto-detection (default: 50)
  description = "My Backend", -- Human-readable, shown in status
})
```

### Backend contract

The `wrap()` function receives a fully resolved policy:

- `policy.rw_paths` is guaranteed to contain only absolute, deduplicated, real filesystem paths. No variables, no relative paths.
- `policy.network` is a boolean (`true` = allow, `false` = block).
- `policy.allow_privileged` is a boolean (`true` = allow sudo, `false` = drop privileges).
- The function must return a flat `string[]` suitable for `vim.fn.jobstart()`, or `nil` + error string.

Environment variables are **not** the backend's concern. They flow through standard process inheritance via `job_opts.env` on the `jobstart()` call.

### Auto-detection

When `backend = "auto"` or `"required"`, Flemma iterates all registered backends in priority order (highest first), calls `available()` on each with its per-backend config, and uses the first that succeeds. Detection results are cached and invalidated when:

- A backend is registered or unregistered (registry generation counter)
- The `backends` config section changes (deep equality check)

This means late registration works: if another plugin registers a backend after Flemma's `setup()`, the next `wrap_command()` call will detect it automatically.

### Unregistering

```lua
sandbox.unregister("my_backend")  -- returns true if found
```

### Introspection

```lua
sandbox.get("bwrap")     -- returns the backend entry or nil
sandbox.get_all()        -- all backends sorted by priority (deep copy)
sandbox.count()          -- number of registered backends
```

---

## Built-in backend: Bubblewrap

The built-in [Bubblewrap](https://github.com/containers/bubblewrap) backend is registered at priority 100 during `setup()`. It requires Linux and the `bwrap` binary.

### What bwrap does

| Flag                | Effect                                                    |
| ------------------- | --------------------------------------------------------- |
| `--ro-bind / /`     | Mount the entire rootfs read-only                         |
| `--bind path path`  | Mount each `rw_paths` entry read-write                    |
| `--dev /dev`        | Provide `/dev` (needed by most tools)                     |
| `--proc /proc`      | Provide `/proc` (needed by Python, Node, etc.)            |
| `--tmpfs /run`      | Writable `/run` for runtime files                         |
| `--unshare-user`    | Drop privileges (when `allow_privileged = false`)         |
| `--unshare-pid`     | Isolate PID namespace                                     |
| `--unshare-uts`     | Isolate hostname                                          |
| `--unshare-ipc`     | Isolate IPC namespace                                     |
| `--share-net`       | Allow network (or `--unshare-net` when `network = false`) |
| `--die-with-parent` | Kill child when parent dies                               |
| `--new-session`     | Prevent keystroke injection                               |

### Process lifecycle

When a sandboxed command times out or is cancelled:

1. `vim.fn.jobstop()` sends `SIGTERM` to the `bwrap` process.
2. `--die-with-parent` propagates the signal to child processes.
3. `--unshare-pid` ensures the PID namespace tears down when PID 1 exits, killing all remaining processes.

This covers the normal case reliably. Background jobs spawned inside the sandbox are killed when the shell exits.

---

## What the sandbox does and does not do

The sandbox limits the blast radius of tool execution. It is effective against the common case – a model that hallucinates a destructive command, writes to the wrong directory, or accidentally clobbers system files. It is **not** a security boundary against a model that is actively trying to cause harm.

### What it prevents

- Writing or deleting files outside `rw_paths` (e.g., `rm -rf /`, overwriting `~/.bashrc`)
- Privilege escalation via `sudo` (when `allow_privileged = false`)
- PID, IPC, and UTS namespace leakage between the sandbox and the host
- Orphan processes surviving after the sandbox exits

### What it does not prevent

- **Data exfiltration.** The sandbox can read all files on the filesystem (read-only). A tool can `cat ~/.ssh/id_rsa` and `curl` it to a remote server. Network access is allowed by default. Set `network = false` to block this, but many tools need network access to function.
- **Damage within writable paths.** Anything inside `rw_paths` is fair game. If your project directory is writable (the default), the model can delete or overwrite any file in it.
- **Sandbox escapes.** The sandbox uses user namespaces and bubblewrap – no root required, no kernel modules. A model that actively exploits kernel vulnerabilities or bwrap bugs could escape. This is not the threat model.

### Known caveats

**`/tmp` is writable by default.** Many tools need a writable temp directory, so `/tmp` is in the default `rw_paths`. Since `/tmp` is a shared namespace on the host, a sandboxed agent could interfere with other users' temp files. Remove it from `rw_paths` or use a private tmpfs (see [Examples](#examples)) if this concerns you.

**Signal propagation is best-effort.** When a sandboxed command times out, Flemma kills the `bwrap` parent. Child processes are terminated via `--die-with-parent` and PID namespace teardown. In practice this is reliable, but a process that has deliberately escaped its session may survive briefly before kernel cleanup catches it.

**Lua-level enforcement covers writes, not reads.** The `write` and `edit` tools check `sandbox.is_path_writable()` before modifying files and refuse operations outside `rw_paths`. The `read` tool is **not** sandboxed and cannot be – the sandbox policy has no read-deny list. The entire rootfs is readable by design (mirroring bwrap's `--ro-bind / /`). This is intentional: restricting reads would break tool functionality broadly, and the real risk from unrestricted reads is data exfiltration, which is better addressed by `network = false` (see above). Note that Lua-level write enforcement works independently of the backend – even on platforms without `bwrap`, the `write` and `edit` tools will enforce the policy when `enabled = true`.

---

## API reference

The sandbox module exposes a public API for tools and plugins:

```lua
local sandbox = require("flemma.sandbox")

-- Configuration
sandbox.resolve_config(opts)          -- Effective config (global + per-buffer + runtime override)
sandbox.is_enabled(opts)              -- Is sandboxing currently enabled?
sandbox.get_policy(bufnr, opts)       -- Resolved policy with path variables expanded

-- Command wrapping
sandbox.wrap_command(inner_cmd, bufnr, opts)  -- Wrap a command array; returns original if disabled

-- Path checking
sandbox.is_path_writable(path, bufnr, opts)   -- Would this path be writable under current policy?

-- Backend management
sandbox.validate_backend(opts)                -- Is a suitable backend available?
sandbox.detect_available_backend(opts)        -- Which backend would be auto-detected?
sandbox.register(name, definition)            -- Register a backend
sandbox.unregister(name)                      -- Remove a backend
sandbox.get(name)                             -- Look up a backend by name
sandbox.get_all()                             -- All backends sorted by priority
sandbox.count()                               -- Number of registered backends
sandbox.setup()                               -- Register built-in backends

-- Runtime toggle
sandbox.set_enabled(enabled)           -- Override enabled state for this session
sandbox.reset_enabled()                -- Clear the runtime override
sandbox.get_override()                 -- Current override value (nil = no override)
```
