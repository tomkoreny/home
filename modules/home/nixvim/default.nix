{ inputs, pkgs, ... }: {
  imports = [
    inputs.nvf.homeManagerModules.default
  ];
  programs.nvf = {
    enable = true;
    # your settings need to go into the settings attribute set
    # most settings are documented in the appendix
    settings = {
      vim = {
        viAlias = true;
        vimAlias = true;
        debugMode = {
          enable = false;
          level = 16;
          logFile = "/tmp/nvim.log";
        };

        spellcheck = {
          enable = true;
        };

        lsp = {
          formatOnSave = true;
          lspkind.enable = true;
          lightbulb.enable = true;
          lspsaga.enable = true;
          trouble.enable = true;
          lspSignature.enable = true;
          otter-nvim.enable = true;
          nvim-docs-view.enable = true;
          presets.tailwindcss-language-server.enable = true;
        };

        debugger = {
          nvim-dap = {
            enable = true;
            ui.enable = true;
          };
        };
        lsp.enable = true;

        # This section does not include a comprehensive list of available language modules.
        # To list all available language module options, please visit the nvf manual.
        languages = {
          enableFormat = true;
          enableTreesitter = true;
          enableExtraDiagnostics = true;

          # Languages that will be supported in default and maximal configurations.
          nix.enable = true;
          markdown.enable = true;
          markdown.lsp.enable = false; # marksman requires swift which is broken on arm64-darwin

          # Languages that are enabled in the maximal configuration.
          bash.enable = true;
          clang.enable = false;
          css.enable = true;
          html.enable = false; # superhtml broken on macOS (zig sandbox issue)
          sql.enable = true;
          java.enable = false;
          kotlin.enable = false;
          typescript.enable = true;
          go.enable = false;
          lua.enable = true;
          zig.enable = false;
          python.enable = true;
          typst.enable = true;
          rust = {
            enable = true;
            extensions.crates-nvim.enable = true;
          };
          #
          # Language modules that are not as common.
          assembly.enable = false;
          astro.enable = false;
          nu.enable = false;
          csharp.enable = false;
          julia.enable = false;
          vala.enable = false;
          scala.enable = false;
          r.enable = false;
          gleam.enable = false;
          dart.enable = false;
          ocaml.enable = false;
          elixir.enable = false;
          haskell.enable = false;
          ruby.enable = false;

          svelte.enable = true;

          # Nim LSP is broken on Darwin and therefore
          # should be disabled by default. Users may still enable
          # `vim.languages.vim` to enable it, this does not restrict
          # that.
          # See: <https://github.com/PMunch/nimlsp/issues/178#issue-2128106096>
          nim.enable = false;
        };

        visuals = {
          nvim-scrollbar.enable = true;
          nvim-web-devicons.enable = true;
          nvim-cursorline.enable = true;
          cinnamon-nvim.enable = true;
          fidget-nvim.enable = true;

          highlight-undo.enable = true;
          indent-blankline.enable = true;

          # Fun
          cellular-automaton.enable = false;
        };

        statusline = {
          lualine = {
            enable = true;
            # theme = "catppuccin";
          };
        };

        theme = {
          enable = true;
          # name = "catppuccin";
          # style = "mocha";
          transparent = false;
        };

        autopairs.nvim-autopairs.enable = true;

        autocomplete.nvim-cmp.enable = true;

        formatter.conform-nvim.enable = true;

        snippets.luasnip.enable = true;

        filetree = {
          nvimTree.enable = true;
        };

        tabline = {
          nvimBufferline.enable = true;
        };

        treesitter.context.enable = true;

        binds = {
          whichKey.enable = true;
          cheatsheet.enable = true;
        };

        telescope.enable = true;

        git = {
          enable = true;
          gitsigns.enable = true;
          gitsigns.codeActions.enable = false; # throws an annoying debug message
        };

        minimap = {
          minimap-vim.enable = false;
          # codewindow was dropped upstream: nvf now asserts on any definition
          # of vim.minimap.codewindow.enable, because it does not support the
          # tree-sitter main branch.
        };

        dashboard = {
          dashboard-nvim.enable = false;
          alpha.enable = true;
        };

        notify = {
          nvim-notify.enable = true;
        };

        projects = {
          project-nvim.enable = true;
        };

        utility = {
          ccc.enable = false;
          vim-wakatime.enable = false;
          diffview-nvim.enable = true;
          yanky-nvim.enable = false;
          icon-picker.enable = true;
          surround.enable = true;
          leetcode-nvim.enable = false;
          multicursors.enable = false;

          motion = {
            hop.enable = true;
            leap.enable = true;
            precognition.enable = false;
          };
          images = {
            image-nvim.enable = false;
          };
        };

        notes = {
          obsidian.enable = false; # FIXME: neovim fails to build if obsidian is enabled
          neorg.enable = false;
          orgmode.enable = false;
          todo-comments.enable = true;
        };

        terminal = {
          toggleterm = {
            enable = true;
            lazygit.enable = true;
          };
        };

        ui = {
          borders.enable = true;
          noice.enable = true;
          colorizer.enable = true;
          modes-nvim.enable = false; # the theme looks terrible with catppuccin
          illuminate.enable = true;
          breadcrumbs = {
            enable = true;
            navbuddy.enable = true;
          };
          smartcolumn = {
            enable = true;
            setupOpts.custom_colorcolumn = {
              # this is a freeform module, it's `buftype = int;` for configuring column position
              nix = "110";
              ruby = "120";
              java = "130";
              go = [
                "90"
                "130"
              ];
            };
          };
          fastaction.enable = true;
        };

        assistant = {
          codecompanion-nvim = {
            enable = true;
            setupOpts = {
              strategies = {
                # ACP adapters (provided by claude-code-acp + codex-acp packages)
                # - Codex as default for chat/inline
                # - Claude Code kept for agent workflow
                chat = {
                  adapter = "codex";
                };
                inline = {
                  adapter = "codex";
                };
                agent = {
                  adapter = "claude_code";
                };
              };
            };
          };
          chatgpt.enable = false;
          copilot = {
            enable = false;
            cmp.enable = false;
          };
        };

        extraPlugins = {
          pi2-nvim = {
            package = pkgs.vimUtils.buildVimPlugin {
              pname = "pi2.nvim";
              version = "unstable-${inputs.pi2-nvim.shortRev or "unknown"}";
              src = inputs.pi2-nvim;
            };
            setup = ''
              require("pi").setup({
                cli = {
                  bin = "${inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp}/bin/omp",
                },
                agent_dir = vim.fn.expand("~/.omp/agent"),
                -- pi2.nvim suppresses its completion notification while the prompt
                -- is focused. Emit it from the RPC event instead so every run is
                -- visible, including runs where we wait in the prompt.
                attention = {
                  notify_on_completion = false,
                },
                rpc = {
                  map_event = function(event)
                    if event.type == "agent_end" then
                      vim.schedule(function()
                        vim.notify(
                          "π │ Agent finished - waiting for your input",
                          vim.log.levels.INFO,
                          { title = "π", timeout = 5000 }
                        )
                      end)
                    end
                    return event
                  end,
                },
              })

              vim.keymap.set({ "n", "v" }, "<Leader>pp", function() vim.cmd("Pi layout=side") end, { desc = "Pi side" })
              vim.keymap.set({ "n", "v" }, "<Leader>pf", function() vim.cmd("Pi layout=float") end, { desc = "Pi float" })
              vim.keymap.set({ "n", "v" }, "<Leader>pl", "<Cmd>PiToggleLayout<CR>", { desc = "Pi toggle layout" })
              vim.keymap.set({ "n", "v" }, "<Leader>pc", "<Cmd>PiContinue<CR>", { desc = "Pi continue last session" })
              vim.keymap.set({ "n", "v" }, "<Leader>pr", "<Cmd>PiResume<CR>", { desc = "Pi resume past session" })
              vim.keymap.set({ "n", "v" }, "<Leader>pm", "<Cmd>PiSendMention<CR>", { desc = "Pi mention file/selection" })
              vim.keymap.set({ "n", "v" }, "<Leader>pa", "<Cmd>PiAttention<CR>", { desc = "Pi open next attention request" })
              vim.keymap.set({ "n", "v" }, "<Leader>pi", "<Cmd>PiPasteImage<CR>", { desc = "Pi paste clipboard image" })

              -- Terminal paste shortcuts only send text, so an image-only clipboard
              -- never reaches Neovim's paste handler. Query it explicitly in π prompts.
              vim.api.nvim_create_autocmd("FileType", {
                pattern = "pi-chat-prompt",
                callback = function(event)
                  vim.keymap.set({ "n", "i" }, "<C-v>", "<Cmd>PiPasteImage<CR>", {
                    buffer = event.buf,
                    desc = "Pi paste clipboard image",
                  })
                end,
              })
            '';
          };
          img-clip-nvim.package = pkgs.vimPlugins.img-clip-nvim;
          render-markdown-nvim.package = pkgs.vimPlugins.render-markdown-nvim;
        };

        session = {
          nvim-session-manager.enable = false;
        };

        gestures = {
          gesture-nvim.enable = false;
        };

        comments = {
          comment-nvim.enable = true;
        };

        presence = {
          neocord.enable = false;
        };
      };
    };
  };
}
