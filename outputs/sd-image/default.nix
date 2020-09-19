let
  nixos = import <nixpkgs/nixos> {
    configuration = { ... }: {
      imports = [
        <nixpkgs/nixos/modules/installer/cd-dvd/system-tezi.nix>
        <machine>
        <image>
      ];

      #sdImage.enable = true;
    };
  };
in
nixos.config.system.build.teziTarballs // {
  inherit (nixos) pkgs system config;
}
