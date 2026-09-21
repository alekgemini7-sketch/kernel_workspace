#!/bin/bash
set -euo pipefail

# ============================================================
# KERNELSU NEXT - LEGACY NON-GKI BUILD
# ============================================================

KERNEL_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"

export KERNEL_ROOT
export ARCH=arm64
export SUBARCH=arm64
export DEFCONFIG="${DEFCONFIG:-a3core_eur_open_defconfig}"

# ============================================================
# DETEKSI & SETUP TOOLCHAIN OTOMATIS
# ============================================================

# 1. Deteksi Clang
if [ -d "${KERNEL_ROOT}/toolchains/clang-r383902b/bin" ]; then
    CLANG_BIN="${KERNEL_ROOT}/toolchains/clang-r383902b/bin"
elif [ -d "${KERNEL_ROOT}/toolchain/clang/bin" ]; then
    CLANG_BIN="${KERNEL_ROOT}/toolchain/clang/bin"
else
    CLANG_BIN="$(dirname "$(command -v clang || echo '/usr/bin/clang')")"
fi

# 2. Deteksi GCC AArch64 (Prioritaskan gcc-14.3 jika ada, fallback ke sistem apt)
if [ -d "${KERNEL_ROOT}/toolchains/gcc-14.3/bin" ]; then
    GCC_BIN="${KERNEL_ROOT}/toolchains/gcc-14.3/bin"
    CROSS_COMPILE="${GCC_BIN}/aarch64-none-linux-gnu-"
    CROSS_COMPILE_ARM32="${GCC_BIN}/arm-none-linux-gnueabihf-"
elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    GCC_BIN="$(dirname "$(command -v aarch64-linux-gnu-gcc)")"
    CROSS_COMPILE="aarch64-linux-gnu-"
    CROSS_COMPILE_ARM32="arm-linux-gnueabihf-"
else
    CROSS_COMPILE="aarch64-linux-android-"
    CROSS_COMPILE_ARM32="arm-linux-androideabi-"
fi

export PATH="${CLANG_BIN}:${GCC_BIN:-/usr/bin}:${PATH}"

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

export CROSS_COMPILE
export CROSS_COMPILE_ARM32
export CLANG_TRIPLE=aarch64-linux-gnu-

export OUT="${KERNEL_ROOT}/out"
export ART="${KERNEL_ROOT}/output_artifacts"

# ============================================================
# HELPERS
# ============================================================

die() {
    echo ""
    echo "=================================================="
    echo "[ERROR] $*"
    echo "=================================================="
    exit 1
}

info() {
    echo ""
    echo "=================================================="
    echo "$*"
    echo "=================================================="
}

# ============================================================
# CHECK TOOLCHAIN
# ============================================================

info "CHECK TOOLCHAIN"

command -v clang >/dev/null 2>&1 || die "clang not found in PATH"
command -v ld.lld >/dev/null 2>&1 || die "ld.lld not found in PATH"
command -v llvm-ar >/dev/null 2>&1 || die "llvm-ar not found in PATH"
command -v gcc >/dev/null 2>&1 || die "Host gcc not found"
command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 || die "AArch64 GCC not found: ${CROSS_COMPILE}gcc"

echo "Clang:"
clang --version | head -n 2

echo ""
echo "Cross GCC:"
"${CROSS_COMPILE}gcc" --version | head -n 1

# ============================================================
# SOURCE CHECK & CLEANUP
# ============================================================

cd "$KERNEL_ROOT"

info "KERNEL SOURCE"
echo "Kernel root: $KERNEL_ROOT"
echo "Defconfig: $DEFCONFIG"

test -f Makefile || die "Kernel Makefile not found."
test -f "arch/arm64/configs/${DEFCONFIG}" || die "Defconfig not found: arch/arm64/configs/${DEFCONFIG}"

info "CLEAN OUTPUT"
rm -rf "$OUT" "$ART"
mkdir -p "$OUT" "$ART" "$ART/dtbs" "$ART/modules"

# ============================================================
# GENERATE DEFCONFIG
# ============================================================

info "GENERATE DEFCONFIG"

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    ARCH="$ARCH" \
    SUBARCH="$SUBARCH" \
    CC="$CC" \
    LD="$LD" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    "$DEFCONFIG"

test -f "$OUT/.config" || die "out/.config was not generated."

# ============================================================
# KERNELSU NEXT CONFIG
# ============================================================

info "ENABLE KERNELSU NEXT CONFIG"

if [ ! -x scripts/config ]; then
    chmod +x scripts/config || true
fi

# Flag wajib KSU Next & Kprobe
scripts/config --file "$OUT/.config" --enable KSU
scripts/config --file "$OUT/.config" --enable KPROBES
scripts/config --file "$OUT/.config" --enable HAVE_KPROBES
scripts/config --file "$OUT/.config" --enable KPROBE_EVENTS
scripts/config --file "$OUT/.config" --enable OVERLAY_FS
scripts/config --file "$OUT/.config" --enable MODULES || true

info "APPLY OLDDEFCONFIG"

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    ARCH="$ARCH" \
    SUBARCH="$SUBARCH" \
    CC="$CC" \
    LD="$LD" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    olddefconfig

# Verifikasi konfigurasi
grep -q '^CONFIG_KSU=y$' "$OUT/.config" || die "CONFIG_KSU=y missing after olddefconfig."
grep -q '^CONFIG_KPROBES=y$' "$OUT/.config" || die "CONFIG_KPROBES=y missing after olddefconfig."

echo "[OK] KernelSU Next & Kprobe configuration verified."

# ============================================================
# DTC YAML COMPATIBILITY PATCH
# ============================================================

info "PATCH OLD DTC"
sed -i '/yamltree\.o/d' scripts/dtc/Makefile 2>/dev/null || true
sed -i '/dt_to_yaml/d' scripts/dtc/dtc.c 2>/dev/null || true

# ============================================================
# BUILD KERNEL IMAGE
# ============================================================

export KBUILD_BUILD_USER="KernelSU-Next"
export KBUILD_BUILD_HOST="GitHub-Actions"
export KBUILD_BUILD_TIMESTAMP="$(date -u '+%a %b %d %T UTC %Y')"

info "BUILD KERNEL IMAGE"

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    -j"$(nproc)" \
    ARCH="$ARCH" \
    SUBARCH="$SUBARCH" \
    CC="$CC" \
    LD="$LD" \
    AR="$AR" \
    NM="$NM" \
    OBJCOPY="$OBJCOPY" \
    OBJDUMP="$OBJDUMP" \
    STRIP="$STRIP" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    Image

test -s "$OUT/arch/arm64/boot/Image" || die "Kernel Image was not generated."

# ============================================================
# BUILD MODULES & DTBS
# ============================================================

info "BUILD KERNEL MODULES"

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    -j"$(nproc)" \
    ARCH="$ARCH" \
    SUBARCH="$SUBARCH" \
    CC="$CC" \
    LD="$LD" \
    AR="$AR" \
    NM="$NM" \
    OBJCOPY="$OBJCOPY" \
    OBJDUMP="$OBJDUMP" \
    STRIP="$STRIP" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    modules || true

info "BUILD DTB / DTBO"

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    -j"$(nproc)" \
    ARCH="$ARCH" \
    SUBARCH="$SUBARCH" \
    CC="$CC" \
    LD="$LD" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    dtbs || echo "[WARN] DTB target skipped or not present."

# ============================================================
# COLLECT ARTIFACTS
# ============================================================

info "COLLECT ARTIFACTS"

cp "$OUT/arch/arm64/boot/Image" "$ART/Image"
cp "$OUT/.config" "$ART/kernel.config"

[ -f "$OUT/System.map" ] && cp "$OUT/System.map" "$ART/System.map"
[ -f "$OUT/Module.symvers" ] && cp "$OUT/Module.symvers" "$ART/Module.symvers"

make -C "$KERNEL_ROOT" O="$OUT" ARCH="$ARCH" kernelrelease > "$ART/kernel.release" 2>/dev/null || echo "4.14-custom" > "$ART/kernel.release"

# Salin DTB/DTBO
find "$OUT/arch/arm64/boot" -type f \( -name '*.dtb' -o -name '*.dtbo' \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
    rel="${file#$OUT/arch/arm64/boot/}"
    mkdir -p "$ART/dtbs/$(dirname "$rel")"
    cp "$file" "$ART/dtbs/$rel"
done

# Salin Modules .ko
find "$OUT" -type f -name '*.ko' -print0 2>/dev/null | while IFS= read -r -d '' file; do
    rel="${file#$OUT/}"
    mkdir -p "$ART/modules/$(dirname "$rel")"
    cp "$file" "$ART/modules/$rel"
done

# Metadata KSU
if [ -d "$KERNEL_ROOT/drivers/kernelsu/.git" ]; then
    git -C "$KERNEL_ROOT/drivers/kernelsu" rev-parse HEAD > "$ART/kernelsu.commit" || true
    git -C "$KERNEL_ROOT/drivers/kernelsu" describe --tags --always > "$ART/kernelsu.version" || true
else
    echo "ksu-next-latest" > "$ART/kernelsu.version"
    echo "unknown" > "$ART/kernelsu.commit"
fi

grep -E '^(CONFIG_KSU|CONFIG_KPROBES|CONFIG_OVERLAY_FS)' "$OUT/.config" > "$ART/kernelsu.config" || true

# ============================================================
# GENERATE CHECKSUMS & FINISH
# ============================================================

info "GENERATE SHA256"

cd "$ART"
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS

info "BUILD FINISHED SUCCESSFULLY"
echo "[OK] Image size: $(ls -lh "$ART/Image" | awk '{print $5}')"
echo "[OK] DTB Count: $(find "$ART/dtbs" -type f | wc -l)"
echo "[OK] Modules Count: $(find "$ART/modules" -type f -name '*.ko' | wc -l)"
