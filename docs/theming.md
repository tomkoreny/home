# Unified theming and accent color

The shared visual theme is Catppuccin Mocha with a true-black background and a
single custom accent color.

## Single source of truth

Change shared colors only in `lib/common/default.nix`:

```nix
stylix.background = "#000000";
stylix.accent = "#219fff";
stylix.accentLight = "#176fb3";
```

Use six-digit `#RRGGBB` values. New themed modules should import
`common.stylix.background` and `common.stylix.accent` instead of hard-coding
another background or accent.

The shared Stylix configuration maps the background to Base16 `base00` and the
accent to `base0D`, the blue and primary accent slot. This propagates them to
Stylix targets on NixOS, nix-darwin, and Home Manager.

Most surfaces are dark-only, so they need `background` and `accent` alone. A few
apps follow the system appearance and cannot be pinned to dark: those pair
Catppuccin Latte with `accentLight`, which is `accent` darkened 30%. The dark
accent only reaches 2.5:1 on Latte's background, below the 3:1 floor these
themes are built with, while `accentLight` reaches 4.7:1 at the same hue.

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
- Microsoft Teams (`teams.cloud.microsoft`, `teams.microsoft.com`) uses a style
  written in this repo, because no Catppuccin userstyle for the current Teams
  exists. Teams renders with Fluent UI v9, whose design tokens are CSS custom
  properties on the `.fui-FluentProvider` wrapper rather than `:root`, so the
  style overrides those tokens with `!important`. It ships both flavors, keyed on
  Teams' own `<html>` theme class (`theme-defaultV2` and `theme-darkV2`) instead
  of `prefers-color-scheme`, so the palette stays in step with the base theme
  Teams picked. Set **Settings -> Appearance -> Follow OS theme** in Teams once
  and it tracks the system appearance, which makes the style track it too.
- Dark Reader uses the shared background plus the shared accent for selections
  and scrollbars while acting as the fallback for other websites. It is disabled
  on Homarr (`dash.home.tomkoreny.com`), Teams and `lemmy.tomkoreny.com` because
  those provide native or generated dark themes; applying its dynamic engine a
  second time turns subtle separators into prominent blue borders, and on Teams
  it would fight the userstyle above.

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

## Ghostty

Ghostty follows the system appearance on its own. `modules/home/stylix/default.nix`
sets `theme = light:stylix-light,dark:stylix`, which Ghostty re-resolves live when
the OS appearance changes - no restart, no new window. Stylix generates the dark
half (`stylix`: Catppuccin Mocha on the shared true black); the light half
(`stylix-light`) is defined next to it and lands in
`~/.config/ghostty/themes/stylix-light` through `programs.ghostty.themes`.

The light palette is Catppuccin's own Latte terminal palette - the values it
ships as Ghostty's built-in `Catppuccin Latte` - with Latte blue replaced by
`common.stylix.accentLight` in the normal and bright slot, mirroring how Stylix
maps the shared accent onto base16 `base0D` on the dark side. ANSI 0 is Latte
`subtext1` rather than the background: base16 puts `base00` in that slot, which
only makes sense for a dark scheme.

Two Ghostty rules matter when editing this:

- **Colours must live in the theme files, never in `programs.ghostty.settings`.**
  Ghostty replays the top-level config over the loaded theme, so a top-level
  `background`, `foreground` or `cursor-color` would apply to *both* modes and
  make light mode black. The generated `~/.config/ghostty/config` deliberately
  carries only `background-opacity`, `command`, the fonts and `theme`.
- **Do not set `window-theme`.** With a split theme Ghostty rewrites the default
  `auto` to `system`, which hands the window chrome to the OS. Pinning it to
  `dark` is the one setting that visibly breaks light mode.
- **`settings.theme` needs `lib.mkForce`.** Stylix defines it at normal priority
  and the option coerces to a list, so a second definition concatenates rather
  than conflicting: two `theme =` lines, last one wins in Ghostty, no evaluation
  error. `programs.ghostty.themes` is a plain attrset and needs no override.
- **Home Manager writes only `~/.config/ghostty/config`**, on macOS as well as
  Linux. macOS additionally loads
  `~/Library/Application Support/com.mitchellh.ghostty/config` *after* it, so
  anything set there wins. That file is hand-maintained here (currently just a
  `keybind`); adding a `theme` to it would silently override this setup.
- Home Manager's `+validate-config` hook only runs when
  `programs.ghostty.package` is non-null. This repo installs Ghostty elsewhere
  and sets it to `null`, so validation is manual - see below.

Verify a change without touching the live config:

```bash
mkdir -p /tmp/gt/ghostty/themes
cp <generated>/ghostty/config /tmp/gt/ghostty/config
cp <generated theme files> /tmp/gt/ghostty/themes/
XDG_CONFIG_HOME=/tmp/gt ghostty +validate-config; echo "exit=$?"
XDG_CONFIG_HOME=/tmp/gt ghostty +show-config | grep -E '^(theme|background|foreground|window-theme) '
```

`+show-config` always resolves the **light** half, so check the dark one by
temporarily setting `theme = stylix` in the throwaway config. Note that on
macOS, `background-opacity` changes still need a full Ghostty restart, and with
`macos-titlebar-style = tabs` (not set here) 1.2.2 does not repaint the titlebar
on an appearance change.

## OMP and Herdr

Both run inside Ghostty, so both have to follow the same appearance or the
terminal ends up light with dark chrome painted on top.

**Herdr** ships Catppuccin in both flavors and can follow the host terminal.
`modules/home/session-management/default.nix` reconciles three keys into
`~/.config/herdr/config.toml`:

```toml
[theme]
auto_switch = true
dark_name = "catppuccin"
light_name = "catppuccin-latte"
```

That file is not a store symlink, because Herdr writes it itself - onboarding
sets `onboarding`, and `herdr config reset-keys` rewrites the whole file. The
activation step runs `herdr-theme.py`, which edits only those keys in place,
validates the result with `tomllib`, and writes only when something changed;
everything else in the file, including the hand-set `[ui]` values, is left
byte-identical. `herdr config check` accepts the result.

`[theme.custom]` is deliberately unused: its overrides sit on top of whichever
flavor is active, so a single shared-accent override would be wrong in one of
the two modes. Each flavor keeps its own Catppuccin blue.

**OMP** picks a theme slot from the terminal background (OSC 11, then
`COLORFGBG`, then a macOS fallback, then dark). Its `theme.light` used to be the
generic built-in `light`, so light mode looked like a dark theme dropped onto a
pale background. `modules/home/agents/default.nix` now generates a real
Catppuccin Latte theme into `~/.omp/agent/themes/catppuccin-latte-stylix.json`
and points `theme.light` at it. The `-stylix` suffix matters: built-in theme
names take precedence over custom files of the same name.

Two conventions in that theme:

- Tokens that must track the terminal (`text`, `toolTitle`, `mdCodeBlock`,
  `syntaxVariable`, `statusLineOutput`, the message-body colours) are set to
  `""`, which OMP renders as "terminal default", so they inherit Ghostty's
  active foreground instead of pinning a second one.
- Text-bearing colours are Latte hues darkened until they clear 4:1 on Latte's
  base, the same rule that produces `accentLight`. Upstream Latte's yellow,
  peach, sky and pink sit at 2.3-2.6:1, which is unreadable for code. Borders,
  background tints and comments keep the pure Latte values.

`theme.dark` stays on OMP's built-in `titanium`; only the light slot was broken.
Switching it to a generated Mocha theme would be the same exercise.

Verify the OMP theme without touching the live agent directory:

```bash
mkdir -p /tmp/ompdir/themes
cp <generated>/catppuccin-latte-stylix.json /tmp/ompdir/themes/
printf 'theme:\n  dark: catppuccin-latte-stylix\n  light: catppuccin-latte-stylix\nsetupVersion: 1\n' \
  > /tmp/ompdir/config.yml
PI_CODING_AGENT_DIR=/tmp/ompdir omp gallery --tool read --state success --width 80 | cat -v
```

Forcing both slots to the light theme sidesteps background detection; the ANSI
codes in the output are the check (`38;2;23;111;179` is the light accent,
`48;2;215;230;217` the success tint). A theme that fails validation makes OMP
fall back to its built-in `dark`, which is easy to mistake for "detection did
not switch".

## Element

`modules/home/element/default.nix` generates two Element custom themes from the
official `catppuccin/element` themes at one pinned commit: **Catppuccin Mocha
(Stylix)**, which replaces Catppuccin's page canvas and blue with
`common.stylix.background` and `common.stylix.accent`, and **Catppuccin Latte
(Stylix)**, which keeps Latte's own surfaces and uses `common.stylix.accentLight`.
Both add the shared sans-serif and monospace fonts.

The generated `config.json` enables custom themes, ships both, and sets
`custom-Catppuccin Mocha (Stylix)` as Element's default. It is installed at:

- macOS: `~/Library/Application Support/Element/config.json`
- Linux: `~/.config/Element/config.json`

Element cannot follow the system appearance with custom themes. Its
`ThemeWatcher.themeBasedOnSystem()` returns only the built-in `light`, `dark` and
high-contrast ids, and turning on **Match system theme** additionally greys out
the theme picker. Leave that option **off** and pick the flavor in
**Settings -> Appearance**; a theme's `is_dark` flag only selects which base
stylesheet Element loads, it never participates in system matching.

There is no workaround. `generateCustomCompoundCSS()` does interpolate a
compound token's *value* into a stylesheet unescaped, so a value can close the
rule and append `@media (prefers-color-scheme: ...)` blocks that would switch the
palette. That was built and tested: the injected CSS is correct and applies
instantly when moved into an untitled `<style>`, but Element's own titled element
never enters the cascade (see the quirks below), so the media queries never take
effect. Nothing in `config.json` can drop that attribute.

Element's existing device or account theme selection also has higher precedence
than `default_theme`, so a profile that already chose a theme keeps it until it
selects one of the two above. Forcing it would require mutating Element's private
browser storage, which is intentionally avoided.

Two upstream quirks are worked around in the generator:

- A theme's `compound` block never reaches the page. Element renders it into a
  `<style title="custom-theme-compound">`, and a titled stylesheet only applies
  while it is the document's selected stylesheet set, which it is not: Element's
  own theme `<link>`s are titled and it switches them by toggling `disabled`.
  Measured on 1.12.26 - the element exists, `sheet.disabled === false`, its rules
  parse, none of them match `<body>`, and copying the same CSS into an *untitled*
  `<style>` applies instantly. So every `--cpd-*` override was silently dropped
  and the accent stayed Element green `#129a78`. The generator re-declares each
  token through `colors`, which Element writes as an inline style on `<body>`.
  The same defect makes a theme's `fonts.faces` inert; `fonts.general` and
  `fonts.monospace` work, because those go through the inline path.
- `catppuccin/element` derives Latte by substituting palette names into the Mocha
  structure, which leaves its numbered ramps running dark-to-light like a dark
  theme. Compound's light ramps run the other way, so the primary button came out
  as a near-white label on a near-white fill. The generator rebuilds the gray ramp
  from the Latte palette in Compound's direction and drops the hue ramps, whose
  semantic tokens stay Catppuccin either way.

Element X on iOS and Android has no theming surface at all: both ship a fixed
Compound palette and expose only a light/dark/system switch, so there is nothing
for this repo to configure.

## Lemmy

`lemmy.tomkoreny.com` is self-hosted, so it is themed on the server instead of
in the browser. The theme lives in the homelab repo at
`apps/services/lemmy/theme/`: SCSS sources, a pinned `build.sh`, and the
compiled `catppuccin.css` that Flux ships as a ConfigMap mounted at
`/app/extra_themes` in the `lemmy-ui` container.

Unlike the rest of this repo, that theme is not dark-only. lemmy-ui serves a
single stylesheet, so the theme carries both flavors and follows the visitor's
`prefers-color-scheme`: Catppuccin Latte in light mode, Catppuccin Mocha on the
shared true black in dark mode.

The theme is a full Bootstrap 5 compile, so it cannot import from this repo. It
duplicates exactly two values from `lib/common/default.nix`,
`stylix.background` and `stylix.accent`; the rest is the upstream Catppuccin
palette. Light mode uses the same accent hue darkened 30% (`#176fb3`), because
`#219fff` only reaches 2.5:1 on Latte's background. After changing either shared
color here, update `apps/services/lemmy/theme/_palette.catppuccin.scss` and
rerun `apps/services/lemmy/theme/build.sh` in that repo.

Because the instance serves the theme itself, `lemmy.tomkoreny.com` needs no
Stylus userstyle and is excluded from Dark Reader. The instance-wide default is
the admin setting `local_site.default_theme`; an account which explicitly picked
another theme keeps it until it selects **catppuccin** in its user settings.

## Microsoft Teams

Teams is themed in the browser only. The `Teams Catppuccin` userstyle above
covers `teams.cloud.microsoft` and `teams.microsoft.com`; the palette is written
in `modules/home/helium/default.nix` because no Catppuccin userstyle exists for
the current Teams.

The desktop app (`/Applications/Microsoft Teams.app`, cask `microsoft-teams`) is
not themeable. It is not Electron: it is a native host embedding Edge WebView2,
with no `app.asar` to patch, all resources code-sealed under a hardened runtime,
and no theme key in `defaults read com.microsoft.teams2` or in managed
preferences. Its `app_settings.json` does carry a `theme` integer, but the app
rewrites that file itself and the setting also roams server-side, so nix cannot
own it. Injecting CSS would need a persistent CDP client attached through
`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`, which is a daemon rather than
configuration and is not worth it for a work application.

So the desktop app keeps Microsoft's own Default or Dark theme. Setting
**Settings -> Appearance -> Follow OS theme** once is worthwhile anyway: that
preference roams to the web client too, and the userstyle keys off whichever base
theme Teams selects.

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
