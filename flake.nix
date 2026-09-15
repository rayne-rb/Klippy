{
  description = "Klippy, a Clippy-inspired desktop pet";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAll (system:
        let pkgs = pkgsFor system; in
        rec {
          # The Godot project, minus editor-local caches (.godot is machine
          # specific and would go stale inside the store anyway).
          klippy-src = pkgs.lib.cleanSourceWith {
            src = ./Klippy.Companion;
            filter = path: _type: baseNameOf path != ".godot";
          };

          # A launcher rather than a baked export: it seeds a writable copy of
          # the project under XDG data (keyed by the source's store path, so a
          # rebuild gives a fresh copy) because Godot writes its .godot import
          # cache into the project directory, which a store path can't be.
          # The seeded copy needs one editor-style import pass before its
          # class_name lookups resolve, exactly like a fresh checkout.
          #
          # mesa.drivers goes on LD_LIBRARY_PATH because off NixOS the nix Godot
          # otherwise can't find the GPU's DRI drivers: GLX comes back with no
          # framebuffer configs and the GLES fallback segfaults in EGL init.
          klippy = pkgs.writeShellScriptBin "klippy" ''
            export LD_LIBRARY_PATH="${pkgs.mesa.drivers}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            data="''${XDG_DATA_HOME:-$HOME/.local/share}/klippy/$(basename ${klippy-src})"
            if [ ! -d "$data" ]; then
              mkdir -p "$(dirname "$data")"
              cp -r ${klippy-src} "$data"
              chmod -R u+w "$data"
              ${pkgs.godot_4}/bin/godot --headless --path "$data" --import >/dev/null 2>&1 || true
            fi
            exec ${pkgs.godot_4}/bin/godot --path "$data" "$@"
          '';

          default = klippy;
        });

      apps = forAll (system: rec {
        klippy = {
          type = "app";
          program = "${self.packages.${system}.klippy}/bin/klippy";
        };
        default = klippy;
      });
    };
}
