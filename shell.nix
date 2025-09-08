{
  pkgs ? import <nixpkgs> { },
}:
let
  packageOverrides = pkgs.callPackage ./python-packages.nix { };
  python = pkgs.python312.override { inherit packageOverrides; };
  pythonWithPackages = python.withPackages (p: [
    p.google-cloud-aiplatform
  ]);
  plenary-nvim = pkgs.vimPlugins.plenary-nvim;
in
pkgs.mkShell {
  name = "flemma-dev-shell";

  shellHook = ''
    PROJECT_ROOT=$(pwd)
    export PROJECT_ROOT
    PLENARY_PATH=${plenary-nvim}
    export PLENARY_PATH
  '';

  buildInputs = with pkgs; [
    google-cloud-sdk
    libsecret
    pythonWithPackages
    # Neovim plug-ins
    plenary-nvim

    (pkgs.aider-chat.withOptional {
      withBrowser = true;
      withPlaywright = true;
    })

    (writeShellApplication {
      name = "flemma-dev";
      text = ''
        set +e

        if [ -z "''${VERTEXAI_PROJECT-}" ]; then
          if [ -f "$PROJECT_ROOT/.env" ]; then
            VERTEXAI_PROJECT=$(grep -oP '(?<=^VERTEXAI_PROJECT=).*' "$PROJECT_ROOT/.env")
            if [ -n "''${VERTEXAI_PROJECT-}" ]; then
              export VERTEXAI_PROJECT
              echo -e "\033[0;32m[flemma-dev] Loaded Vertex project name from .env file: $VERTEXAI_PROJECT\033[0m"
            else
              echo -e "\033[0;33m[flemma-dev] Warning: \$VERTEXAI_PROJECT was not set in .env file.\033[0m"
            fi
          else
            echo -e "\033[0;33m[flemma-dev] Warning: \$VERTEXAI_PROJECT was not set and no .env file found.\033[0m"
          fi
        fi

        if [ -z "''${GOOGLE_APPLICATION_CREDENTIALS-}" ]; then
          if command -v secret-tool >/dev/null 2>&1; then
            CREDENTIALS=$(secret-tool lookup service vertex key api project_id "''${VERTEXAI_PROJECT-}" 2>/dev/null)
            if [ -n "''${CREDENTIALS-}" ]; then
              existing=$(trap -p EXIT | awk -F"'" '{print $2}')
              # shellcheck disable=SC2064
              trap "( rm -f '$PROJECT_ROOT/.aider-credentials.json'; $existing )" EXIT
              echo "$CREDENTIALS" >"$PROJECT_ROOT/.aider-credentials.json"
              GOOGLE_APPLICATION_CREDENTIALS="$PROJECT_ROOT/.aider-credentials.json"
              export GOOGLE_APPLICATION_CREDENTIALS
              echo -e "\033[0;32m[flemma-dev] Retrieved Google credentials from system keyring.\033[0m"
            else
              echo -e "\033[0;33m[flemma-dev] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and not found in system keyring.\033[0m"
            fi
          else
            echo -e "\033[0;33m[flemma-dev] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and libsecret tools not available.\033[0m"
          fi
        fi

        if [ -z "''${OPENAI_API_KEY-}" ]; then
          if command -v secret-tool >/dev/null 2>&1; then
            OPENAI_API_KEY=$(secret-tool lookup service openai key api 2>/dev/null)
            if [ -n "''${OPENAI_API_KEY-}" ]; then
              export OPENAI_API_KEY
              echo -e "\033[0;32m[flemma-dev] Retrieved OpenAI credentials from system keyring.\033[0m"
            else
              echo -e "\033[0;33m[flemma-dev] Warning: \$OPENAI_API_KEY was not set and not found in system keyring.\033[0m"
            fi
          else
            echo -e "\033[0;33m[flemma-dev] Warning: \$OPENAI_API_KEY was not set and libsecret tools not available.\033[0m"
          fi
        fi

        # shellcheck disable=SC2046
        aider $( find . -name "*.lua" -or -name README.md -or -path "*/syntax/*" ) "$@"

        rm -f .aider-credentials.json || true
      '';
    })

    (writeShellApplication {
      name = "flemma-fmt";
      runtimeInputs = [
        nixfmt-tree
        nodejs_22.pkgs.prettier
        stylua
      ];
      text = ''
        treefmt

        find . -name "*.lua" -print0 | xargs -0 \
        stylua --indent-type spaces --indent-width 2

        find . -name "*.md" -print0 | xargs -0 \
        prettier --write
      '';
    })
  ];
}
