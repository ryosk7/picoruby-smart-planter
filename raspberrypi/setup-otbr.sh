#!/bin/bash
# Install OpenThread Border Router (ot-br-posix) on Raspberry Pi OS (64-bit).
# Run on the Raspberry Pi 5 as the login user (sudo is used where needed).
set -ex
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
sudo apt-get -y install git
cd ~
[ -d ot-br-posix ] || git clone --depth 1 https://github.com/openthread/ot-br-posix.git
cd ot-br-posix
git submodule update --init --depth 1
export DEBIAN_FRONTEND=noninteractive
./script/bootstrap
# The Pi joins the home LAN over Wi-Fi, so the infrastructure interface is wlan0.
INFRA_IF_NAME=wlan0 ./script/setup
echo OTBR_INSTALL_DONE
