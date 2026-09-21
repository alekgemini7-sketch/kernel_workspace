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

command -v clang >/dev/null 2>&1 \
    || die "clang not found"

command -v ld.lld >/dev/null 2>&1 \
    || die "ld.lld not found"

command -v llvm-ar >/dev/null 2>&1 \
    || die "llvm-ar not found"

command -v gcc >/dev/null 2>&1 \
    || die "gcc not found"

command -v ld.bfd >/dev/null 2>&1 \
    || die "ld.bfd not found"

test -x "${CROSS_COMPILE}gcc" \
    || die "AArch64 GCC not found: ${CROSS_COMPILE}gcc"

echo "clang:"
clang --version | head -n 2

echo ""
echo "ld.lld:"
ld.lld --version | head -n 1

echo ""
echo "gcc:"
gcc --version | head -n 1

echo ""
echo "AArch64 GCC:"
"${CROSS_COMPILE}gcc" --version | head -n 1

# ============================================================
# SOURCE CHECK
# ============================================================

cd "$KERNEL_ROOT"

info "KERNEL SOURCE"

echo "Kernel root:"
echo "$KERNEL_ROOT"

echo ""
echo "Defconfig:"
echo "$DEFCONFIG"

test -f Makefile \
    || die "Kernel Makefile not found."

test -f "arch/arm64/configs/${DEFCONFIG}" \
    || die "Defconfig not found: arch/arm64/configs/${DEFCONFIG}"

# ============================================================
# CLEAN OUTPUT
# ============================================================

info "CLEAN OUTPUT"

rm -rf "$OUT"
rm -rf "$ART"

mkdir -p "$OUT"
mkdir -p "$ART"
mkdir -p "$ART/dtbs"
mkdir -p "$ART/modules"

echo "[OK] Output directory cleaned."

# ============================================================
# IMPORTANT:
# Do NOT run git clean here.
#
# KernelSU Next has already been integrated by workflow.
# Running git clean after integration would delete it.
# ============================================================

# ============================================================
# DEFCONFIG
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

test -f "$OUT/.config" \
    || die "out/.config was not generated."

echo "[OK] Defconfig generated."

# ============================================================
# CONFIG TOOL
# ============================================================

info "PREPARE CONFIG TOOL"

if [ ! -x scripts/config ]; then
    chmod +x scripts/config || true
fi

if [ ! -x scripts/config ]; then
    echo "[+] Building kernel scripts..."

    make -C "$KERNEL_ROOT" \
        O="$OUT" \
        ARCH="$ARCH" \
        HOSTCC="$HOSTCC" \
        HOSTCXX="$HOSTCXX" \
        HOSTLD="$HOSTLD" \
        scripts
fi

test -x scripts/config \
    || die "scripts/config unavailable."

# ============================================================
# KERNELSU NEXT CONFIG
# ============================================================

info "ENABLE KERNELSU NEXT"

scripts/config \
    --file "$OUT/.config" \
    --enable KSU

scripts/config \
    --file "$OUT/.config" \
    --enable KPROBES

scripts/config \
    --file "$OUT/.config" \
    --enable KPROBE_EVENTS

scripts/config \
    --file "$OUT/.config" \
    --enable KSU_KPROBE_HOOKS

# Keep module support enabled where possible.
scripts/config \
    --file "$OUT/.config" \
    --enable MODULES || true

# ============================================================
# OLDDEFCONFIG
# ============================================================

info "OLDDEFCONFIG"

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

# ============================================================
# CONFIG VERIFICATION
# ============================================================

info "KERNELSU CONFIG VERIFICATION"

echo "KSU:"
grep -nE \
    '^CONFIG_KSU=|^# CONFIG_KSU' \
    "$OUT/.config" || true

echo ""
echo "KPROBE:"
grep -nE \
    '^CONFIG_KPROBES=|^CONFIG_KPROBE_EVENTS=|^CONFIG_KSU_KPROBE_HOOKS=' \
    "$OUT/.config" || true

echo ""

grep -q '^CONFIG_KSU=y$' \
    "$OUT/.config" \
    || die "CONFIG_KSU=y missing."

grep -q '^CONFIG_KPROBES=y$' \
    "$OUT/.config" \
    || die "CONFIG_KPROBES=y missing."

grep -q '^CONFIG_KPROBE_EVENTS=y$' \
    "$OUT/.config" \
    || die "CONFIG_KPROBE_EVENTS=y missing."

grep -q '^CONFIG_KSU_KPROBE_HOOKS=y$' \
    "$OUT/.config" \
    || die "CONFIG_KSU_KPROBE_HOOKS=y missing."

echo "[OK] KernelSU Next configuration verified."

# ============================================================
# OLD DTC YAML COMPATIBILITY
# ============================================================

info "PATCH OLD DTC"

# Some vendor 4.14 trees contain old YAML DTC support
# incompatible with the host environment.
sed -i '/yamltree\.o/d' scripts/dtc/Makefile || true
sed -i '/dt_to_yaml/d' scripts/dtc/dtc.c || true

echo "[OK] DTC compatibility patch applied."

# ============================================================
# BUILD ENVIRONMENT
# ============================================================

export KBUILD_BUILD_USER="KernelSU-Next"
export KBUILD_BUILD_HOST="GitHub-Actions"
export KBUILD_BUILD_TIMESTAMP="$(date -u '+%a %b %d %T UTC %Y')"

# ============================================================
# BUILD IMAGE
# ============================================================

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

test -s "$OUT/arch/arm64/boot/Image" \
    || die "Kernel Image was not generated."

echo ""
echo "Image:"
ls -lh "$OUT/arch/arm64/boot/Image"

file "$OUT/arch/arm64/boot/Image"

# ============================================================
# BUILD MODULES
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
    modules

MODULE_COUNT="$(
    find "$OUT" \
        -type f \
        -name '*.ko' \
        | wc -l
)"

echo ""
echo "Kernel modules:"
echo "$MODULE_COUNT"

# ============================================================
# BUILD DTBS
# ============================================================

info "BUILD DTB / DTBO"

if make -C "$KERNEL_ROOT" \
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
    dtbs
then
    echo "[OK] DTB target completed."
else
    echo "[WARN] DTB target returned an error."
    echo "[WARN] Continuing with any DTB/DTBO already generated."
fi

# ============================================================
# COLLECT IMAGE
# ============================================================

info "COLLECT IMAGE"

cp \
    "$OUT/arch/arm64/boot/Image" \
    "$ART/Image"

# ============================================================
# COLLECT CONFIG
# ============================================================

cp \
    "$OUT/.config" \
    "$ART/kernel.config"

# ============================================================
# KERNEL RELEASE
# ============================================================

make -C "$KERNEL_ROOT" \
    O="$OUT" \
    ARCH="$ARCH" \
    CC="$CC" \
    LD="$LD" \
    HOSTCC="$HOSTCC" \
    HOSTCXX="$HOSTCXX" \
    HOSTLD="$HOSTLD" \
    kernelrelease \
    > "$ART/kernel.release"

# ============================================================
# SYSTEM MAP
# ============================================================

if [ -f "$OUT/System.map" ]; then
    cp "$OUT/System.map" "$ART/System.map"
fi

# ============================================================
# MODULE SYMVERS
# ============================================================

if [ -f "$OUT/Module.symvers" ]; then
    cp "$OUT/Module.symvers" "$ART/Module.symvers"
fi

# ============================================================
# COLLECT DTB / DTBO
# ============================================================

info "COLLECT DTB / DTBO"

find "$OUT/arch/arm64/boot" \
    -type f \
    \( -name '*.dtb' -o -name '*.dtbo' \) \
    -print0 \
    | while IFS= read -r -d '' file; do

        rel="${file#$OUT/arch/arm64/boot/}"

        mkdir -p \
            "$ART/dtbs/$(dirname "$rel")"

        cp "$file" \
            "$ART/dtbs/$rel"
    done

DTB_COUNT="$(
    find "$ART/dtbs" \
        -type f \
        \( -name '*.dtb' -o -name '*.dtbo' \) \
        | wc -l
)"

echo "DTB/DTBO count: $DTB_COUNT"

# ============================================================
# COLLECT MODULES
# ============================================================

info "COLLECT MODULES"

find "$OUT" \
    -type f \
    -name '*.ko' \
    -print0 \
    | while IFS= read -r -d '' file; do

        rel="${file#$OUT/}"

        mkdir -p \
            "$ART/modules/$(dirname "$rel")"

        cp "$file" \
            "$ART/modules/$rel"
    done

# ============================================================
# KSU METADATA
# ============================================================

info "KERNELSU METADATA"

if [ -d "$KERNEL_ROOT/drivers/kernelsu/.git" ]; then

    git -C "$KERNEL_ROOT/drivers/kernelsu" \
        rev-parse HEAD \
        > "$ART/kernelsu.commit" || true

    git -C "$KERNEL_ROOT/drivers/kernelsu" \
        describe --tags --always \
        > "$ART/kernelsu.version" || true

else

    echo "unknown" > "$ART/kernelsu.commit"
    echo "unknown" > "$ART/kernelsu.version"

fi

# ============================================================
# KSU CONFIG
# ============================================================

grep -E \
    '^(CONFIG_KSU|CONFIG_KPROBES|CONFIG_KPROBE_EVENTS|CONFIG_KSU_KPROBE_HOOKS|CONFIG_MODULES)' \
    "$OUT/.config" \
    > "$ART/kernelsu.config" || true

# ============================================================
# KSU UAPI INSPECTION
# ============================================================

{
    echo "KernelSU Next UAPI inspection"
    echo "================================"
    echo ""

    grep -Rni \
        -E 'UAPI_VERSION|uapi_version|KERNEL_SU_UAPI_VERSION' \
        "$KERNEL_ROOT/drivers/kernelsu" \
        --include='*.h' \
        --include='*.c' \
        2>/dev/null || true

} > "$ART/kernelsu.uapi"

# ============================================================
# FINAL VERIFICATION
# ============================================================

info "FINAL VERIFICATION"

test -s "$ART/Image" \
    || die "Final Image missing."

test -s "$ART/kernel.config" \
    || die "Final kernel.config missing."

test -s "$ART/kernel.release" \
    || die "Final kernel.release missing."

test -s "$ART/kernelsu.config" \
    || die "Final kernelsu.config missing."

echo "[OK] Image exists."
ls -lh "$ART/Image"

echo ""
echo "File type:"
file "$ART/Image"

echo ""
echo "Kernel release:"
cat "$ART/kernel.release"

echo ""
echo "KernelSU version:"
cat "$ART/kernelsu.version" || true

echo ""
echo "KernelSU commit:"
cat "$ART/kernelsu.commit" || true

echo ""
echo "DTB/DTBO count:"
find "$ART/dtbs" \
    -type f \
    \( -name '*.dtb' -o -name '*.dtbo' \) \
    | wc -l

echo ""
echo "Module count:"
find "$ART/modules" \
    -type f \
    -name '*.ko' \
    | wc -l

# ============================================================
# SHA256
# ============================================================

info "GENERATE SHA256"

cd "$ART"

find . \
    -type f \
    ! -name SHA256SUMS \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    > SHA256SUMS

cat SHA256SUMS

# ============================================================
# ARTIFACT LIST
# ============================================================

info "FINAL ARTIFACT LIST"

find "$ART" \
    -type f \
    -exec ls -lh {} \;

info "BUILD FINISHED SUCCESSFULLY"

echo "[OK] KernelSU Next build completed."
echo "[OK] Image generated."
echo "[OK] DTB/DTBO collected."
echo "[OK] Modules collected."
echo "[OK] Metadata generated."
echo "[OK] SHA256SUMS generated."
