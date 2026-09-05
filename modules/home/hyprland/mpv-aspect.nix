{ replaceVars, coreutils }:
replaceVars ./mpv-aspect.lua {
  mkdir = "${coreutils}/bin/mkdir";
}
