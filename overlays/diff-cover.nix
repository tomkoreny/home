# diff-cover 10.5.1 fails six HTML-report integration tests on nixos-unstable
# 02c087f (NixOS/nixpkgs#576851), on Hydra and on both hosts here. It is a
# dependency of sqlfluff, which nvf puts in the Neovim config, so every
# nixos-upgrade and darwin auto-upgrade failed from 2026-10-20. Upstream fixed
# it by moving to 10.6.0 (NixOS/nixpkgs#576855, master 53b5d4e).
#
# Scoped to 10.5.1, so the channel picking up 10.6.0 drops the override.
final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyFinal: pyPrev: {
      diff-cover =
        if pyPrev.diff-cover.version == "10.5.1" then
          pyPrev.diff-cover.overridePythonAttrs (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_added_file_pycodestyle_html"
              "test_added_file_pyflakes_html"
              "test_added_file_pylint_html"
              "test_all_reports"
              "test_fail_under_html"
              "test_fail_under_pass_html"
            ];
          })
        else
          pyPrev.diff-cover;
    })
  ];
}
