# Unified theming and accent color

The shared visual theme is Catppuccin Mocha with a true-black background and a
single custom accent color.

## Single source of truth

Change shared colors only in `lib/common/default.nix`:

```nix
stylix.background = "#000000";
stylix.accent = "#219fff";
```

Use six-digit `#RRGGBB` values. New themed modules should import
`common.stylix.background` and `common.stylix.accent` instead of hard-coding
another background or accent.

The shared Stylix configuration maps the background to Base16 `base00` and the
accent to `base0D`, the blue and primary accent slot. This propagates them to
Stylix targets on NixOS, nix-darwin, and Home Manager.

## Helium website themes

`modules/home/helium/default.nix` imports `common.stylix.accent` and uses it to
generate all browser theme artifacts:

- GitHub and YouTube use the official Catppuccin userstyles with the Catppuccin
  Mocha base replaced by the shared true-black background and their blue and
  accent replaced by the shared accent.
- Notion uses the community Catppuccin userstyle with its background, blue, and
  primary accent replaced by the shared values.
- `nextcloud.home.tomkoreny.com` uses the community `byted/catppuccin-nextcloud`
  CSS, scoped to that host and rewritten to use the shared background and accent.
  It targets the Nextcloud 32+ variable schema; the current instance is Nextcloud 34.
- Dark Reader uses the shared background plus the shared accent for selections
  and scrollbars while acting as the fallback for other websites. It is disabled
  on Homarr (`dash.home.tomkoreny.com`) and Teams because both provide native dark
  themes; applying its dynamic engine a second time turns subtle separators into
  prominent blue borders.

The generated GitHub and YouTube styles inline a pinned Catppuccin Less library.
Their upstream auto-update metadata is deliberately removed so an update cannot
replace the custom accent. Update the pinned inputs in Nix and re-import instead.

## Fonts

Font families have the same source of truth in `lib/common/default.nix` under
`common.stylix.fonts`. Helium consumes those values rather than duplicating font
names:

- Web content uses `SFProDisplay Nerd Font` through the generated `Stylix Fonts`
  userstyle.
- `pre`, `code`, `kbd`, and similar elements use
  `JetBrainsMono Nerd Font Mono`.
- Dark Reader uses the shared sans-serif font on fallback websites.
- The shared serif family is `NewYork Nerd Font`.

The Home Manager Stylix module is enabled on both Linux and macOS and enables
Ghostty's Home Manager module without installing a duplicate package. Ghostty
therefore uses `JetBrainsMono Nerd Font Mono`, the generated `stylix` terminal
palette, and the shared terminal font size. Stylix scales the macOS size by 4/3
to account for Ghostty's 72 DPI macOS baseline versus 96 DPI on Linux.

Chromium does not expose a managed policy for default font families, and Stylix
has no Helium target. Browser chrome therefore continues to use the operating
system UI font (SF Pro on macOS); the generated style controls website content.
Re-import the Stylus file after changing any shared font.

## Element

`modules/home/element/default.nix` generates an Element custom theme from the
official Catppuccin Mocha/Blue theme. It replaces Catppuccin's base and blue with
`common.stylix.background` and `common.stylix.accent`, and adds the shared
sans-serif and monospace fonts.

The generated `config.json` enables custom themes and sets
`custom-Catppuccin Mocha (Stylix)` as Element's default. It is installed at:

- macOS: `~/Library/Application Support/Element Nightly/config.json`
- Linux: `~/.config/Element/config.json`

Element's existing device or account theme selection has higher precedence than
`default_theme`. A profile which has already selected **Match system theme** or a
built-in theme must disable that option and select **Catppuccin Mocha (Stylix)**
once. Forcing it would require mutating Element's private browser storage, which
is intentionally avoided.

## Applying a change

After changing a shared color or font:

1. Apply the configuration with `sw`.
2. Fully quit and reopen Helium so declarative extension changes are loaded.
3. Import `~/.config/helium/stylus-catppuccin-import.json` from Stylus's
   **Manage → Import** screen.
4. Import `~/.config/helium/dark-reader-settings.json` from Dark Reader's
   **Settings → Advanced → Import Settings** screen.

Re-importing the Stylus file updates the existing styles by name.

## Why the extension imports are not automatic

The extensions themselves are installed declaratively from pinned CRX files,
and Nix generates both import files. Applying those imports is not exposed as a
browser policy or command-line API:

- Stylus keeps its styles in extension-owned IndexedDB storage.
- Dark Reader keeps its settings in isolated extension storage.
- Neither extension publishes a Chromium managed-storage policy schema for
  these settings.

Writing their profile databases from Home Manager would require Helium to be
stopped and would depend on private storage schemas, risking lost settings or a
corrupted browser profile. UI automation would also be platform-specific and
fragile, so the configuration intentionally keeps the one-time import manual.

A fully automatic alternative would be a small Nix-built browser extension that
injects the three site styles directly and marks those pages as already themed
for Dark Reader. That removes the Stylus import but requires maintaining and
signing our own extension; Dark Reader's own fallback settings would still need
either a one-time import or a maintained fork.
