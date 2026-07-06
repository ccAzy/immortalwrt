define Device/cudy_tr3000-v1-ubootmod
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := v1 (OpenWrt U-Boot layout)
  DEVICE_DTS := mt7981b-cudy-tr3000-v1-ubootmod
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb sysupgrade.bin
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | \
	fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  ARTIFACTS := preloader.bin bl31-uboot.fip
  ARTIFACT/preloader.bin := mt7981-bl2 cudy-ddr3
  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot cudy_tr3000-v1
endef