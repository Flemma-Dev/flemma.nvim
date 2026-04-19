{
  pkgs ? import <nixpkgs> { },
}:
let
  nodejs_lts = pkgs.nodejs_24;
  plenary-nvim = pkgs.vimPlugins.plenary-nvim;
in
pkgs.mkShell rec {
  name = "flemma-dev-shell";

  shellHook = ''
    PROJECT_ROOT=$(pwd)
    export PROJECT_ROOT

    PLENARY_PATH=${plenary-nvim}
    export PLENARY_PATH
  '';

  buildInputs = with pkgs; [
    actionlint
    bubblewrap
    gh
    google-cloud-sdk
    libsecret
    links2
    nodejs_lts.pkgs.pnpm
    socat
    vhs
    # Neovim plug-ins
    plenary-nvim
    # Lua tools
    lua-language-server
    lua54Packages.luacheck

    (writeShellScriptBin "mcporter" ''
      exec ${lib.getExe envchain} mcp_keys pnpm --silent --package=mcporter@latest dlx -- mcporter "$@"
    '')

    (writeShellApplication {
      name = "flemma-fmt";
      runtimeInputs = [
        nixfmt-tree
        nodejs_lts.pkgs.prettier
        shfmt
        stylua
      ];
      text = ''
        treefmt

        find . -name "*.lua" -print0 | xargs -0 \
        stylua

        find . -name "*.sh" -print0 | xargs -0 \
        shfmt -w -i 2 -ci

        find . -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) -not -name 'pnpm-lock.yaml' -not -path '*/.claude/*' -not -path '*/contrib/*' -print0 | xargs -0 \
        prettier --write
      '';
    })

    (writeShellApplication {
      name = "flemma-amp";
      text = "exec pnpm --silent --package=@sourcegraph/amp@latest dlx -- amp \"$@\"";
    })

    (writeShellApplication {
      name = "flemma-claude";
      text = "exec pnpm --silent --package=@anthropic-ai/claude-code@latest dlx -- claude \"$@\"";
    })

    (writeShellApplication {
      name = "flemma-codex";
      text = "exec pnpm --silent --package=@openai/codex dlx -- codex \"$@\"";
    })
  ];
}
