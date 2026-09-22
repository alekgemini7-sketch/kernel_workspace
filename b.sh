#!/bin/bash
set -euo pipefail

# ============================================================
# INITIALIZATION & PATHS
# ============================================================

export KERNEL_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
export ARCH=arm64
export SUBARCH=arm64
export DEFCONFIG="${DEFCONFIG:-a3core_eur_open_defconfig}"

export TOOLCHAIN="${KERNEL_ROOT}/toolchains"
export CLANG_BIN="${TOOLCHAIN}/clang-r383902b/bin"
export GCC_BIN="${TOOLCHAIN}/gcc-14.3/bin"

export PATH="${CLANG_BIN}:${GCC_BIN}:${PATH}"

export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

export HOSTCC=gcc
export HOSTCXX=g++
export HOSTLD=ld.bfd

export CROSS_COMPILE="${GCC_BIN}/aarch64-none-linux-gnu-"
export CROSS_COMPILE_ARM32="${GCC_BIN}/arm-none-linux-gnueabihf-"
export CLANG_TRIPLE=aarch64-linux-gnu-

export OUT="${KERNEL_ROOT}/out"
export ART="${KERNEL_ROOT}/output_artifacts"

# ============================================================
# PREPARE ENVIRONMENT
# ============================================================

echo "[+] Membersihkan folder output..."
rm -rf "$OUT" "$ART"
mkdir -p "$OUT" "$ART"

# ============================================================
# CONFIGURE DEFCONFIG
# ============================================================

echo "[+] Membuat defconfig..."
make -C "$KERNEL_ROOT" O="$OUT" ARCH="$ARCH" SUBARCH="$SUBARCH" CC="$CC" LD="$LD" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" "$DEFCONFIG"

echo "[+] Menyiapkan script config..."
if [ ! -x scripts/config ]; then
    make -C "$KERNEL_ROOT" O="$OUT" ARCH="$ARCH" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" scripts
fi

echo "[+] Injecting KernelSU Next (Manual Hook) ke Defconfig..."
scripts/config --file "$OUT/.config" --enable KSU
scripts/config --file "$OUT/.config" --enable KSU_MANUAL_HOOK
scripts/config --file "$OUT/.config" --disable KPROBES
scripts/config --file "$OUT/.config" --disable KPROBE_EVENTS
scripts/config --file "$OUT/.config" --disable KSU_TRACEPOINT_HOOK || true
scripts/config --file "$OUT/.config" --disable KSU_SUSFS || true
scripts/config --file "$OUT/.config" --enable OVERLAY_FS
make -C "$KERNEL_ROOT" O="$OUT" ARCH="$ARCH" SUBARCH="$SUBARCH" CC="$CC" LD="$LD" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" olddefconfig

# ============================================================
# PATCH & BUILD
# ============================================================

echo "[+] Patch DTC Compatibility..."
sed -i '/yamltree\.o/d' scripts/dtc/Makefile || true
sed -i '/dt_to_yaml/d' scripts/dtc/dtc.c || true

export KBUILD_BUILD_USER="KernelSU-Next"
export KBUILD_BUILD_HOST="GitHub-Actions"

echo "[+] Memulai Kompilasi Image Kernel..."
make -C "$KERNEL_ROOT" O="$OUT" -j"$(nproc)" ARCH="$ARCH" SUBARCH="$SUBARCH" CC="$CC" LD="$LD" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" CROSS_COMPILE="$CROSS_COMPILE" CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" CLANG_TRIPLE="$CLANG_TRIPLE" Image

# ============================================================
# COLLECT ARTIFACTS
# ============================================================

echo "[+] Mengumpulkan Hasil Build..."
if [ -s "$OUT/arch/arm64/boot/Image" ]; then
    cp "$OUT/arch/arm64/boot/Image" "$ART/Image"
    cp "$OUT/.config" "$ART/kernel.config"
    make -C "$KERNEL_ROOT" O="$OUT" ARCH="$ARCH" CC="$CC" LD="$LD" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" kernelrelease > "$ART/kernel.release"
    
    echo "[OK] Build Sukses! File Image ditemukan."
else
    echo "[ERROR] Image kernel gagal di-build!"
    exit 1
fi
