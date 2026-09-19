#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail

sdk=${1:?Usage: build-router-armv7.sh <OpenWrt SDK path> [Cargo target dir]}
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain=$(find "$sdk/staging_dir" -maxdepth 1 -type d -name 'toolchain-arm_cortex-a7*' -print -quit)
test -n "$toolchain"
toolbin="$toolchain/bin"
triple=armv7_unknown_linux_musleabihf
export PATH="$HOME/.cargo/bin:$sdk/staging_dir/host/bin:$PATH"
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER="$toolbin/arm-openwrt-linux-muslgnueabi-gcc"
export CC_armv7_unknown_linux_musleabihf="$toolbin/arm-openwrt-linux-muslgnueabi-gcc"
export CXX_armv7_unknown_linux_musleabihf="$toolbin/arm-openwrt-linux-muslgnueabi-g++"
export AR_armv7_unknown_linux_musleabihf="$toolbin/arm-openwrt-linux-muslgnueabi-ar"
export BINDGEN_EXTRA_CLANG_ARGS_armv7_unknown_linux_musleabihf="--target=armv7-unknown-linux-musleabihf --sysroot=$toolchain"
export RUSTFLAGS='--cfg libc_unstable_musl_v1_2_3'
export CARGO_TARGET_DIR=${2:-$sdk/gozarbin-cargo-target}

cd "$repo/aether"
cargo build --locked --release --features tor --target armv7-unknown-linux-musleabihf
file "$CARGO_TARGET_DIR/armv7-unknown-linux-musleabihf/release/aether"
