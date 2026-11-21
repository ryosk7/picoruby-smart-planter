# RCP ファームウェア（2 台目の ISP1807 Dev Board）

Raspberry Pi 5 に USB でつなぐ ISP1807 Dev Board には、OpenThread の RCP（Radio Co-Processor）ファームウェア `ot-rcp` を書き込みます。
本書では、R2P2-nRF が取り込んでいる `ot-nrf528xx`（コミット c1fe23b）から、USB 接続版をビルドしました。

## ビルド（macOS）

`arm-none-eabi-gcc`、CMake、Ninja、Ruby を用意し、R2P2-nRF を `--recursive` で clone しておきます。

```console
OT=R2P2-nRF/components/picoruby-nRF/nrf52/openthread
cmake -S $OT -B build-ot-rcp -G Ninja \
  -DNRF_PLATFORM=nrf52840 \
  -DCMAKE_TOOLCHAIN_FILE=$OT/src/nrf52840/arm-none-eabi.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DOT_PLATFORM=external -DOT_BOOTLOADER=USB -DOT_USB=ON \
  -DOT_EXTERNAL_MBEDTLS=nordicsemi-mbedtls \
  -DOT_RCP=ON -DOT_FTD=OFF -DOT_MTD=OFF \
  -DOT_APP_RCP=ON -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF
cmake --build build-ot-rcp --target ot-rcp
arm-none-eabi-objcopy -O ihex build-ot-rcp/bin/ot-rcp ot-rcp.hex
ruby R2P2-nRF/tools/uf2conv.rb -c -f 0xADA52840 -o ot-rcp.uf2 ot-rcp.hex
```

## 書き込み

1. ISP1807 Dev Board のリセットボタンを 2 回すばやく押して、UF2 ブートローダーのモードにします（`NRF52BOOT` ドライブが見えます）。
2. `ot-rcp.uf2` を `NRF52BOOT` にコピーします。
3. ボードが再起動したら、Raspberry Pi 5 に USB でつなぎます。`ls /dev/serial/by-id/` に `usb-Nordic_Semiconductor_nRF528xx_OpenThread_Device_<シリアル>-if00` が出れば成功です。
