{ config, pkgs, ... }:
let
  toradex_apalis_imx6 = import ./system.nix;
  kernel = toradex_apalis_imx6.platform.kernelTarget;
  init = "${config.system.build.toplevel}/init";
  root = "/dev/mmcblk2p2";
  uboot = pkgs.buildUBoot {
    defconfig = "apalis_imx6_defconfig";
    extraMeta.platforms = [ toradex_apalis_imx6.system ];
    filesToInstall = [ "SPL" "u-boot.img" ];
  };
  uEnv = pkgs.writeText "uEnv.txt" ''
    bootdir=
    bootcmd=run uenvcmd;
    bootfile=${kernel}
    fdtfile=${toradex_apalis_imx6.dtb}
    loadaddr=0x11000000
    fdtaddr=0x12000000
    loadfdt=load mmc 0:1 ''${fdtaddr} ''${fdtfile}
    loaduimage=load mmc 0:1 ''${loadaddr} ''${bootfile}
    uenvcmd=mmc rescan; run loaduimage; run loadfdt; run fdtboot
    fdtboot=run mmc_args; bootz ''${loadaddr} - ''${fdtaddr}
    mmc_args=setenv bootargs console=''${console} ''${optargs} root=${root} rootfstype=ext4 init=${init}
  '';

  prepareScript = pkgs.writeText "prepare.sh" ''
    #!/bin/sh
    #
    # (c) Toradex AG 2016
    #
    # Empty in-field hardware update script
    #
      
    PRODUCT_ID=$1
    BOARD_REV=$2
    SERIAL=$3
    IMAGE_FOLDER=$4
      
    error_exit () {
            echo "$1" 1>&2
            exit 1
    }
      
    exit 0
  '';

  wrapupScript = pkgs.writeText "wrapup.sh" ''
    #!/bin/sh
    #
    # (c) Toradex AG 2016-2017
    #
    # Apalis/Colibri iMX6 in-field hardware update script
    #
    # One-time configurations (non-reversible!):
    # - Fuse SoC to use eMMC Fast Boot mode
    # - Enable eMMC H/W reset capabilities
    # Required configurations
    # - Configure Boot Bus mode (due to eMMC Fast Boot mode above)
    #
    # Other configurations
    # - Boot from eMMC boot partition (must run as wrap-up script)
    #

    PRODUCT_ID=$1
    BOARD_REV=$2
    SERIAL=$3
    IMAGE_FOLDER=$4

    error_exit () {
    echo "$1" 1>&2
    exit 1
    }

    # Do a basic validation that we do this on one of our modules
    case $PRODUCT_ID in
    0027|0028|0029|0035) ;;
    0014|0015|0016|0017) ;;
    *) error_exit "This script is meant to be run on a Apalis/Colibri iMX6. Aborting...";
    esac

    # Fuse SoC's BOOT_CFG to enable eMMC Fast Boot mode, if necessary
    # WARNING: Fusing is a one-time operation, do not change values
    # here unless you are absolutely sure what your are doing.
    BOOT_CFG=0x5072
    if [ ! -f /sys/fsl_otp/HW_OCOTP_CFG4 ]; then
    echo "Fusing not supported."
    elif grep -q ''${BOOT_CFG} /sys/fsl_otp/HW_OCOTP_CFG4; then
    echo "No new value for BOOT_CFG required."
    else
    echo ''${BOOT_CFG} > /sys/fsl_otp/HW_OCOTP_CFG4
    if [ "$?" != "0" ]; then
            error_exit "Writing fuse BOOT_CFG failed! Aborting..."
    fi
    echo "Fuse BOOT_CFG updated to ''${BOOT_CFG}."
    fi

    # eMMC configurations
    MMCDEV=/dev/mmcblk0

    # Enable eMMC H/W Reset feature. This need to be executed before the other
    # eMMC settings, it seems that this command resets all settings.
    # Since this is a one-time operation, it will fail the second time. Ignore
    # errors and redirect stderr to stdout.
    mmc hwreset enable ''${MMCDEV} 2>&1
    if [ "$?" == "0" ]; then
    echo "H/W Reset permanently enabled on ''${MMCDEV}"
    fi

    # Set boot bus mode
    if ! mmc bootbus set single_hs x1 x8 ''${MMCDEV}; then
    error_exit "Setting boot bus mode failed"
    fi

    # Enable eMMC boot partition 1 (mmcblkXboot0) and boot ack
    # Make sure everything hit the eMMC when execute this command. Otherwise
    # the eMMC will reset the configuration.
    sync
    if ! mmc bootpart enable 1 1 ''${MMCDEV}; then
    error_exit "Setting bootpart failed"
    fi

    mmc extcsd read ''${MMCDEV} | grep -e BOOT_BUS_CONDITIONS -e PARTITION_CONFIG -e RST_N_FUNCTION

    echo "Apalis/Colibri iMX6 in-field hardware update script ended successfully."

    exit 0
  '';

  imageJSON = pkgs.writeText "image.json" (builtins.toJSON {
    autoinstall = false;
    blockdevs = [
      {
        name = "mmcblk0";
        partitions = [
          {
            partition_size_nominal = 16;
            want_maximised = false;
            content = {
              filename = "Apalis-iMX6_Qt5-X11-Image.bootfs.tar.xz";
              filesystem_type = "FAT";
              label = "nixos_boot";
              mkfs_options = "";
              #uncompressed_size = 5.80469;
            };
          }
          {
            content = {
              partition_size_nominal = 512;
              want_maximised = true;
              filename = "Apalis-iMX6_Qt5-X11-Image.rootfs.tar.xz";
              filesystem_type = "ext4";
              label = "nixos_root";
              mkfs_options = "-E nodiscard";
              #uncompressed_size = 1078.1;
            };
          }
        ];
      }
      {
        name = "mmcblk0boot0";
        content = {
          filesystem_type = "raw";
          rawfiles = [
            {
              dd_options = "seek=2";
              filename = "SPL";
            }
            {
              dd_options = "seek=138";
              filename = "u-boot.img";
            }
          ];
        };
      }
    ];
    config_format = 2;
    description = "NixOS system.";
    #icon = "toradexlinux.png";
    #marketing = "marketing.tar";
    name = "NixOS system";
    prepare_script = "prepare.sh";
    supported_product_ids = [ "0027" "0028" "0029" "0035" ];
    u_boot_env = "uEnv.txt";
    version = "0.1";
    wrapup_script = "wrapup.sh";
  });
in {
  # specify the system we're compiling to
  nixpkgs.crossSystem = toradex_apalis_imx6;

  # enable free firmware
  hardware.enableRedistributableFirmware = false;

  # specify a good kernel version
  boot.kernelPackages = pkgs.linuxPackages_5_4;

  # do our own boot-loader
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  # no firmware for our board for now
  sdImage.populateFirmwareCommands = "";

  sdImage.compressImage = false;

  # Populate result/nix-support/tezi folder for ToradexEasyInstaller.
  sdImage.postImageBuildCommands = ''
    mkdir -p $out/tezi-image/
    cp ${uboot}/SPL $out/tezi-image/
    cp ${uboot}/u-boot.img $out/tezi-image/
    cp ${uEnv} $out/tezi-image/uEnv.txt
    cp ${prepareScript} $out/tezi-image/prepare.sh
    cp ${wrapupScript} $out/tezi-image/wrapup.sh
    mkdir -p $out/tezi-image/boot
    cp ${config.boot.kernelPackages.kernel}/${kernel} $out/tezi-image/boot/
    cp ${config.boot.kernelPackages.kernel}/dtbs/${toradex_apalis_imx6.dtb} $out/tezi-image/boot/
  '';

  # build & install boot loader
  sdImage.populateRootCommands = "";

  teziTarballs.populateBootCommands = ''
    cp ${config.boot.kernelPackages.kernel}/${kernel} ./boot/
    cp ${config.boot.kernelPackages.kernel}/dtbs/${toradex_apalis_imx6.dtb} ./boot/
  '';
}
