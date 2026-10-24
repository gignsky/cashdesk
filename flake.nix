{
  description = "CashDesk: Cash Consulting's branded RustDesk client";

  inputs = {
    # Lord G.'s "super nixpkgs": nixpkgs plus the gigpkgs overlay, branch gigpkgs-unstable.
    nixpkgs.url = "github:gignsky/gigpkgs/gigpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Tool versions come from upstream's workflow so they never drift from CI.
      workflow = builtins.readFile ./.github/workflows/flutter-build.yml;
      # Matched line by line: a regex over the whole file overflows Nix's regex stack.
      versionFromWorkflow =
        name:
        let
          matches = builtins.filter (m: m != null) (
            map (line: builtins.match "  ${name}: \"([^\"]+)\".*" line) (nixpkgs.lib.splitString "\n" workflow)
          );
        in
        if matches == [ ] then
          throw "${name} not found in flutter-build.yml"
        else
          builtins.head (builtins.head matches);
      flutterVersion = versionFromWorkflow "FLUTTER_VERSION";
      rustVersion = versionFromWorkflow "RUST_VERSION";
      flutterAttr =
        "flutter" + builtins.replaceStrings [ "." ] [ "" ] (builtins.substring 0 4 flutterVersion);
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      packages = forAllSystems (pkgs: {
        brand-icons = pkgs.stdenvNoCC.mkDerivation {
          pname = "cashdesk-brand-icons";
          version = "1";
          src = ./brand;
          nativeBuildInputs = [
            pkgs.librsvg
            (pkgs.python3.withPackages (ps: [ ps.pillow ]))
          ];
          buildPhase = ''
            runHook preBuild
            python3 gen-icons.py --out $out
            runHook postBuild
          '';
          dontInstall = true;
        };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.brand-icons;
      });

      apps = forAllSystems (pkgs: {
        apply-brand = {
          type = "app";
          meta.description = "Run brand/apply.sh against the working tree";
          program = pkgs.lib.getExe (
            pkgs.writeShellApplication {
              name = "apply-brand";
              runtimeInputs = [
                pkgs.git
                pkgs.gnugrep
                pkgs.perl
                pkgs.coreutils
                pkgs.diffutils
                pkgs.findutils
              ];
              text = ''
                exec bash "$(git rev-parse --show-toplevel)/brand/apply.sh" "$@"
              '';
            }
          );
        };
      });

      checks = forAllSystems (pkgs: {
        shellcheck = pkgs.runCommand "cashdesk-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck ${./brand}/*.sh
          touch $out
        '';
        nixfmt =
          pkgs.runCommand "cashdesk-nixfmt"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
            }
            ''
              nixfmt --check ${./flake.nix}
              touch $out
            '';
        brand-icons = self.packages.${pkgs.stdenv.hostPlatform.system}.brand-icons;
      });

      devShells = forAllSystems (
        pkgs:
        let
          hasRustdesk = pkgs ? rustdesk-flutter;
          # The versioned attribute is a throwing alias once nixpkgs drops it, hence tryEval.
          flutterTry = builtins.tryEval (pkgs.${flutterAttr} or pkgs.flutter);
          flutter = if flutterTry.success then flutterTry.value else pkgs.flutter;
          # Linux build dependencies, used only when gigpkgs has no rustdesk-flutter to inherit from.
          fallbackDeps = with pkgs; [
            clang
            llvmPackages.libclang
            cmake
            pkg-config
            nasm
            gtk3
            libvpx
            libopus
            libaom
            libyuv
            xdotool
            pam
            alsa-lib
            pulseaudio
            gst_all_1.gstreamer
            gst_all_1.gst-plugins-base
            gst_all_1.gst-plugins-good
            libxcb
            xorg.libXfixes
            xorg.libXrandr
            libva
            openssl
          ];
        in
        {
          default = pkgs.mkShell {
            inputsFrom = pkgs.lib.optional hasRustdesk pkgs.rustdesk-flutter;
            packages = [
              pkgs.rustup
              flutter
              pkgs.python3
              pkgs.gh
              pkgs.jq
              pkgs.nushell
              pkgs.imagemagick
              pkgs.librsvg
              pkgs.shellcheck
              pkgs.nixfmt
            ]
            ++ pkgs.lib.optionals (!hasRustdesk) fallbackDeps;
            RUST_VERSION = rustVersion;
            FLUTTER_VERSION = flutterVersion;
            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
            shellHook = ''
              echo "CashDesk devShell: upstream pins rust ${rustVersion}, flutter ${flutterVersion}"
              echo "  rustup toolchain install ${rustVersion}   # once; rustup is on PATH"
              echo "  flutter here: $(flutter --version 2>/dev/null | head -1 || echo unavailable)"
              ${pkgs.lib.optionalString (
                !hasRustdesk
              ) ''echo "  note: gigpkgs has no rustdesk-flutter; using the explicit dependency list"''}
              echo "  branding: nix run .#apply-brand   (needs RENDEZVOUS_SERVER RS_PUB_KEY CC_APP_NAME)"
            '';
          };
        }
      );
    };
}
