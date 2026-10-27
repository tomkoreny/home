{
  lib,
  python3Packages,
  fetchFromGitHub,
  wrapGAppsHook4,
  gobject-introspection,
  gtk4,
  libadwaita,
  libsecret,
  gdk-pixbuf,
  glib,
  bluez,
  coreutils,
  wl-clipboard,
}:
let
  # Main rather than v0.8.1: call notifications, the oFono call controller and
  # call history landed after that release.
  rev = "027392765e6fcc31811128add4f3d03c96c286ad";
in
python3Packages.buildPythonApplication {
  pname = "blueferry";
  version = "0.8.1-unstable-2026-10-26";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "erikwb";
    repo = "blueferry";
    inherit rev;
    hash = "sha256-y8EPaZOrpvZ/B9bQ+boDKP1k+lbBGyPXlTbFTdh6qxw=";
  };

  # Upstream hard-codes FHS paths (/usr/bin/btmgmt, /usr/bin/systemctl, the
  # packaged helper in /usr/lib/blueferry). --replace-fail turns an upstream
  # move into a build failure instead of a silently broken feature.
  postPatch = ''
    substituteInPlace src/blueferry/bluetooth_capabilities.py \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail '"/usr/bin/systemctl"' '"/run/current-system/sw/bin/systemctl"' \
      --replace-fail '"/usr/lib/bluetooth/bluetoothd",' '"${bluez}/libexec/bluetooth/bluetoothd",'
    substituteInPlace src/blueferry/bluez_setup.py \
      --replace-fail '"/usr/lib/blueferry/blueferry-set-cod"' "\"$out/libexec/blueferry/blueferry-set-cod\"" \
      --replace-fail '"/usr/bin/sudo"' '"/run/wrappers/bin/sudo"' \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail '"/usr/bin/systemctl"' '"/run/current-system/sw/bin/systemctl"'
    substituteInPlace src/blueferry/service_manager.py \
      --replace-fail '"/usr/bin/systemctl"' '"/run/current-system/sw/bin/systemctl"'
    substituteInPlace src/blueferry/cli.py \
      --replace-fail '"/usr/libexec/bluetooth/obexd"' '"${bluez}/libexec/bluetooth/obexd"'
    substituteInPlace src/blueferry/client_activation.py \
      --replace-fail 'Path("/usr/bin")' "Path(\"$out/bin\")"
    substituteInPlace src/blueferry/backend_lifecycle.py \
      --replace-fail '"/usr/share/blueferry/package-release"' "\"$out/share/blueferry/package-release\""
    substituteInPlace src/blueferry/build_info.py \
      --replace-fail '"/usr/share/blueferry/build-sha"' "\"$out/share/blueferry/build-sha\""
    substituteInPlace src/blueferry/wireplumber_policy.py \
      --replace-fail '"/usr/bin/wireplumber"' '"/run/current-system/sw/bin/wireplumber"'
    substituteInPlace src/blueferry/plugin_manager.py \
      --replace-fail '"/bin/false"' '"${coreutils}/bin/false"'

    substituteInPlace systemd/blueferry.service packaging/arch/io.weirdware.BlueFerry.service \
      --replace-fail /usr/bin/blueferry "$out/bin/blueferry"
    substituteInPlace systemd/blueferry-btmgmt-set-class@.service \
      --replace-fail /usr/lib/blueferry/blueferry-set-cod "$out/libexec/blueferry/blueferry-set-cod"
    substituteInPlace systemd/blueferry-set-cod \
      --replace-fail /usr/bin/env '${coreutils}/bin/env' \
      --replace-fail /usr/bin/btmgmt '${bluez}/bin/btmgmt'
  '';

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  dependencies = with python3Packages; [
    cryptography
    dbus-python
    phonenumbers
    pygobject3
    regex
    textual
    typer
  ];

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
  ];

  # Typelibs: Secret for the encrypted history key, Gtk/Adw/GdkPixbuf for the
  # GTK client.
  buildInputs = [
    gdk-pixbuf
    glib
    gtk4
    libadwaita
    libsecret
  ];

  postInstall = ''
    # Only the GTK client is packaged; the Qt client needs PySide6 and Kirigami.
    rm -r "$out/bin/blueferry-qt" "$out/bin/blueferry-tray" \
      "$out/${python3Packages.python.sitePackages}/blueferry/qt"

    install -Dm644 systemd/blueferry.service "$out/lib/systemd/user/blueferry.service"
    install -Dm644 systemd/blueferry-btmgmt-set-class@.service \
      "$out/lib/systemd/system/blueferry-btmgmt-set-class@.service"
    install -Dm755 systemd/blueferry-set-cod "$out/libexec/blueferry/blueferry-set-cod"
    install -Dm644 packaging/arch/io.weirdware.BlueFerry.service \
      "$out/share/dbus-1/services/io.weirdware.BlueFerry.service"
    install -Dm644 data/io.weirdware.BlueFerry.xml \
      "$out/share/dbus-1/interfaces/io.weirdware.BlueFerry.xml"
    install -Dm644 data/icons/io.weirdware.BlueFerry.svg \
      "$out/share/icons/hicolor/scalable/apps/io.weirdware.BlueFerry.svg"
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.desktop \
      "$out/share/applications/io.weirdware.BlueFerry.Gtk.desktop"
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.metainfo.xml \
      "$out/share/metainfo/io.weirdware.BlueFerry.Gtk.metainfo.xml"

    # Clients compare these with the running backend and restart a stale one,
    # which is what replaces the old daemon after a rebuild.
    install -d "$out/share/blueferry"
    printf '%s\n' "$version" > "$out/share/blueferry/package-release"
    printf '%s\n' ${rev} > "$out/share/blueferry/build-sha"
  '';

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix PATH : ${
        lib.makeBinPath [
          bluez
          wl-clipboard
        ]
      }
    )
  '';

  # Upstream's suite needs an isolated dbus-run-session and both GUI toolkits.
  doCheck = false;
  pythonImportsCheck = [ "blueferry.cli" ];

  meta = {
    description = "iPhone messages, notifications, contacts and calls on Linux over Bluetooth";
    homepage = "https://github.com/erikwb/blueferry";
    license = lib.licenses.gpl2Plus;
    mainProgram = "blueferry";
    platforms = lib.platforms.linux;
  };
}
