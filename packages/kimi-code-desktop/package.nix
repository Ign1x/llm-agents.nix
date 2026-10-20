{
  lib,
  flake,
  stdenvNoCC,
  platformSource,
  mkUpdater,
  dpkg,
  unzip,
  formatelf,
  makeWrapper,
  makeShellWrapper,
  copyDesktopItems,
  makeDesktopItem,
  wrapGAppsHook3,
  desktop-file-utils,
  codesignCheckHook,
  mkCodesignCheck,
  fd,
  ripgrep,
  xdg-utils,
  adwaita-icon-theme,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libayatana-appindicator,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  systemdLibs,
  vulkan-loader,
  wayland,
}:

let
  pname = "kimi-code-desktop";
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-amd64.deb";
      aarch64-darwin = "mac-arm64.zip";
    };
    urlTemplate = "https://code.kimi.com/kimi-code/desktop/binaries/{version}/KimiCode-{version}-{platform}";
  };
  inherit (stdenvNoCC.hostPlatform) isLinux isDarwin;
  teamId = "2J9472RW75";
  agentTools = [
    fd
    ripgrep
  ];
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version src;

  nativeBuildInputs =
    lib.optionals isLinux [
      makeWrapper
      dpkg
      formatelf
      copyDesktopItems
      wrapGAppsHook3
    ]
    ++ lib.optionals isDarwin [
      unzip
      makeShellWrapper
    ];

  buildInputs = lib.optionals isLinux [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk3
    libgbm
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    nspr
    nss
    pango
    systemdLibs
  ];

  # Chromium loads these through dlopen rather than DT_NEEDED.
  runtimeDependencies = lib.optionals isLinux [
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libXcursor
    pipewire
    wayland
  ];
  # ANGLE loads the GL/Vulkan drivers from shared objects as well.
  appendRunpaths = lib.optionals isLinux [
    (lib.makeLibraryPath [
      libglvnd
      vulkan-loader
    ])
  ];

  dontStrip = true;
  # Keep the upstream macOS bundle and its Developer ID signatures intact.
  dontFixup = isDarwin;
  # Only wrap the launcher: libexec also contains loadable libraries and addons.
  dontWrapGApps = true;
  sourceRoot = ".";

  unpackPhase = lib.optionalString isLinux ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase =
    if isLinux then
      ''
        runHook preInstall

        mkdir -p "$out/libexec" "$out/bin" "$out/share"
        cp -a 'opt/Kimi Code' "$out/libexec/${pname}"
        cp -a usr/share/icons usr/share/metainfo "$out/share/"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/Applications" "$out/bin"
        cp -a 'Kimi Code.app' "$out/Applications/"
        # The external launcher leaves every upstream Mach-O signature intact.
        makeShellWrapper "$out/Applications/Kimi Code.app/Contents/MacOS/Kimi Code" \
          "$out/bin/${pname}" \
          --prefix PATH : ${lib.makeBinPath agentTools}

        runHook postInstall
      '';

  preFixup = lib.optionalString isLinux ''
    makeWrapper "$out/libexec/${pname}/kimi-code" "$out/bin/${pname}" \
      --prefix PATH : ${lib.makeBinPath (agentTools ++ [ xdg-utils ])} \
      "''${gappsWrapperArgs[@]}"
  '';

  desktopItems = lib.optionals isLinux [
    (makeDesktopItem {
      name = "kimi-code";
      desktopName = "Kimi Code";
      comment = "Kimi Code Desktop";
      exec = "${pname} %U";
      icon = "kimi-code";
      startupWMClass = "Kimi Code";
      categories = [ "Development" ];
      mimeTypes = [ "x-scheme-handler/kimi-code" ];
    })
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs =
    lib.optionals isLinux [
      desktop-file-utils
    ]
    ++ lib.optionals isDarwin [ codesignCheckHook ];
  codesignTeamId = teamId;
  installCheckPhase = ''
    runHook preInstallCheck
    ${lib.optionalString isLinux ''
      export HOME=$(mktemp -d)
      ELECTRON_RUN_AS_NODE=1 "$out/bin/${pname}" \
        ${./runtime-smoke.cjs} "$out/libexec/${pname}" ${lib.escapeShellArg source.version} \
        ${stdenvNoCC.shell}
      desktop-file-validate "$out/share/applications/kimi-code.desktop"
      grep -Fx 'Exec=${pname} %U' "$out/share/applications/kimi-code.desktop"
      grep -Ex 'MimeType=x-scheme-handler/kimi-code;?' "$out/share/applications/kimi-code.desktop"
      test -f "$out/share/icons/hicolor/512x512/apps/kimi-code.png"
      test -f "$out/share/metainfo/com.kimi.code.desktop.metainfo.xml"
    ''}
    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Coding Agents";
    tests.codesign = mkCodesignCheck {
      name = pname;
      inherit teamId;
      srcs = source.darwinSrcs;
    };
    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://code.kimi.com/kimi-code/desktop/latest-linux.yml";
          regex = ''(?m)^version: ([0-9]+\.[0-9]+\.[0-9]+)$'';
        };
      }
    );
  };

  meta = {
    description = "Desktop interface for Kimi Code's agentic coding workflows";
    homepage = "https://www.kimi.com/code";
    changelog = "https://code.kimi.com/kimi-code/desktop/binaries/${source.version}/changelog.en.md";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.Ign1x ];
    mainProgram = pname;
    platforms = source.platforms;
  };
}
