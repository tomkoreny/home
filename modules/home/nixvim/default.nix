{inputs, ...}: {
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
  ];
  programs.nixvim = {
    enable = true;
    globals.mapleader = " ";
    opts = {
      tabstop = 2;
      shiftwidth = 2;
      expandtab = true;
      mouse = "a";
    };

    plugins.lualine.enable = true;
    plugins.typescript-tools.enable = true;

    plugins.auto-save.enable = true;
    plugins.auto-session.enable = true;
    plugins.coq-nvim.enable = true;
    plugins.coq-nvim.settings.auto_start = true;
    plugins.treesitter = {
      enable = true;
      settings.highlight.enable = true;
      settings.indent.enable = true;
    };
    plugins.telescope.enable = true;
    plugins.nvim-tree.enable = true;
    plugins.mini.enable = true;
    plugins.mini.modules.icons = {
      style = "glyph";
    };
    plugins.mini.mockDevIcons = true;

    plugins.lsp.enable = true;
    plugins.lsp.inlayHints = true;

    colorschemes.catppuccin.enable = true;

    keymaps = [
      {
        action = "<cmd>Telescope find_files<CR>";
        key = "<leader>ff";
      }
      {
        action = "<cmd>Telescope git_files<CR>";
        key = "<leader>fg";
      }
      {
        action = "<cmd>Telescope buffers<CR>";
        key = "<leader>fb";
      }
    ];
  };
}
