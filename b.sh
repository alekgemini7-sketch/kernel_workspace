#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SukiSU Ultra - Kernel 4.14 / non-GKI / SharkL3
# ============================================================

export KERNEL_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"

export ARCH=arm64
export SUBARCH=arm64

export TOOLCHAIN_DIR="${KERNEL_ROOT}/toolchain_download"
export CLANG_DIR="${TOOLCHAIN_DIR}/clang-r383902b"
export GCC_DIR="${TOOLCHAIN_DIR}/gcc-14.3"

export CLANG_BIN="${CLANG_DIR}/bin"
export GCC_BIN="${GCC_DIR}/bin"

export PATH="${CLANG_BIN}:${GCC_BIN}:${PATH}"

export CC="${CLANG_BIN}/clang"
export HOSTCC="${CLANG_BIN}/clang"

export LD="${CLANG_BIN}/ld.lld"
export AR="${CLANG_BIN}/llvm-ar"
export NM="${CLANG_BIN}/llvm-nm"
export OBJCOPY="${CLANG_BIN}/llvm-objcopy"
export OBJDUMP="${CLANG_BIN}/llvm-objdump"
export STRIP="${CLANG_BIN}/llvm-strip"
export READELF="${CLANG_BIN}/llvm-readelf"

export LLVM=1
export LLVM_IAS=1

export CLANG_TRIPLE=aarch64-linux-gnu-

export CROSS_COMPILE="${GCC_BIN}/aarch64-none-linux-gnu-"
export CROSS_COMPILE_ARM32="${GCC_BIN}/arm-none-linux-gnueabihf-"

export BSP_BUILD_FAMILY=sharkl3
export BSP_BUILD_ANDROID_OS=y

export DEFCONFIG=a3core_eur_open_defconfig

export KBUILD_BUILD_USER="SukiSU"
export KBUILD_BUILD_HOST="SharkL3"
export KBUILD_BUILD_TIMESTAMP="$(date -u '+%a %b %d %T UTC %Y')"

export KCFLAGS="-march=armv8.2-a+crypto -mtune=cortex-a55 -fno-semantic-interposition"

OUT="${KERNEL_ROOT}/out"
ART="${KERNEL_ROOT}/output_artifacts"

# ============================================================
# FUNCTIONS
# ============================================================

die() {
    echo ""
    echo "=================================================="
    echo "[ERROR] $*"
    echo "=================================================="
    exit 1
}

run_make() {
    make \
        -C "${KERNEL_ROOT}" \
        O="${OUT}" \
        ARCH="${ARCH}" \
        CC="${CC}" \
        HOSTCC="${HOSTCC}" \
        LD="${LD}" \
        AR="${AR}" \
        NM="${NM}" \
        OBJCOPY="${OBJCOPY}" \
        OBJDUMP="${OBJDUMP}" \
        STRIP="${STRIP}" \
        READELF="${READELF}" \
        LLVM="${LLVM}" \
        LLVM_IAS="${LLVM_IAS}" \
        CROSS_COMPILE="${CROSS_COMPILE}" \
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
        CLANG_TRIPLE="${CLANG_TRIPLE}" \
        BSP_BUILD_FAMILY="${BSP_BUILD_FAMILY}" \
        BSP_BUILD_ANDROID_OS="${BSP_BUILD_ANDROID_OS}" \
        "$@"
}

# ============================================================
# CHECK TOOLCHAIN
# ============================================================

echo "=================================================="
echo "TOOLCHAIN CHECK"
echo "=================================================="

command -v clang >/dev/null \
    || die "clang not found"

command -v ld.lld >/dev/null \
    || die "ld.lld not found"

command -v llvm-ar >/dev/null \
    || die "llvm-ar not found"

command -v "${CROSS_COMPILE}gcc" >/dev/null \
    || die "AArch64 GCC not found"

clang --version | head -n 1
ld.lld --version | head -n 1
"${CROSS_COMPILE}gcc" --version | head -n 1

# ============================================================
# CLEAN OUTPUT
# ============================================================

echo ""
echo "=================================================="
echo "CLEAN OUTPUT"
echo "=================================================="

rm -rf "${OUT}"
rm -rf "${ART}"

mkdir -p "${OUT}"
mkdir -p "${ART}"

# ============================================================
# SUKISU INTEGRATION
# ============================================================

echo ""
echo "=================================================="
echo "INTEGRATE SUKISU ULTRA"
echo "=================================================="

cd "${KERNEL_ROOT}"

if [ ! -d "${KERNEL_ROOT}/drivers/kernelsu" ]; then

    curl -LSs \
        "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
        | bash -s builtin

fi

[ -d "${KERNEL_ROOT}/drivers/kernelsu" ] \
    || die "SukiSU integration failed"

echo "[OK] drivers/kernelsu exists."

# ============================================================
# DEFCONFIG
# ============================================================

echo ""
echo "=================================================="
echo "DEFCONFIG"
echo "=================================================="

run_make "${DEFCONFIG}"

[ -f "${OUT}/.config" ] \
    || die ".config was not generated"

# ============================================================
# CONFIGURE NON-GKI SUKISU
# ============================================================

echo ""
echo "=================================================="
echo "CONFIGURE NON-GKI SUKISU"
echo "=================================================="

./scripts/config --enable CONFIG_KSU

# Non-GKI hook
./scripts/config --enable CONFIG_KSU_MANUAL_HOOK

# Do not use Kprobe hook as primary method
./scripts/config --disable CONFIG_KSU_KPROBES_KSUD || true

# Disable experimental components for first build
./scripts/config --disable CONFIG_KPM || true
./scripts/config --disable CONFIG_KSU_SUSFS || true
./scripts/config --disable CONFIG_KSU_TRACEPOINT_HOOK || true

# Preserve these if supported
if grep -q 'CONFIG_KSU_LSM_SECURITY_HOOKS' "${OUT}/.config"; then
    ./scripts/config --enable CONFIG_KSU_LSM_SECURITY_HOOKS || true
fi

if grep -q 'CONFIG_KSU_FEATURE_ADBROOT' "${OUT}/.config"; then
    ./scripts/config --enable CONFIG_KSU_FEATURE_ADBROOT || true
fi

if grep -q 'CONFIG_KSU_FEATURE_SULOG' "${OUT}/.config"; then
    ./scripts/config --enable CONFIG_KSU_FEATURE_SULOG || true
fi

run_make olddefconfig

echo ""
echo "SukiSU configuration:"

grep -E \
    '^CONFIG_KSU=|^CONFIG_KSU_MANUAL_HOOK=|^CONFIG_KSU_KPROBES_KSUD=|^CONFIG_KSU_SUSFS=|^CONFIG_KPM=' \
    "${OUT}/.config" || true

grep -q '^CONFIG_KSU=y$' "${OUT}/.config" \
    || die "CONFIG_KSU=y missing"

grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "${OUT}/.config" \
    || die "CONFIG_KSU_MANUAL_HOOK=y missing"

# ============================================================
# BUILD IMAGE
# ============================================================

echo ""
echo "=================================================="
echo "BUILD IMAGE"
echo "=================================================="

run_make \
    -j"$(nproc)" \
    KCFLAGS="${KCFLAGS}" \
    Image

[ -f "${OUT}/arch/arm64/boot/Image" ] \
    || die "Image build failed"

# ============================================================
# BUILD MODULES
# ============================================================

echo ""
echo "=================================================="
echo "BUILD MODULES"
echo "=================================================="

run_make \
    -j"$(nproc)" \
    KCFLAGS="${KCFLAGS}" \
    modules

# ============================================================
# BUILD DTBS
# ============================================================

echo ""
echo "=================================================="
echo "BUILD DTBS"
echo "=================================================="

run_make \
    -j"$(nproc)" \
    dtbs || echo "[WARN] dtbs target failed/skipped"

# ============================================================
# VERIFY IMAGE
# ============================================================

echo ""
echo "=================================================="
echo "KERNEL IMAGE"
echo "=================================================="

ls -lh "${OUT}/arch/arm64/boot/Image"

file "${OUT}/arch/arm64/boot/Image"

echo ""
echo "SHA256:"
sha256sum "${OUT}/arch/arm64/boot/Image"

# ============================================================
# COLLECT ARTIFACT
# ============================================================

echo ""
echo "=================================================="
echo "COLLECT ARTIFACT"
echo "=================================================="

mkdir -p "${ART}/dtbs"
mkdir -p "${ART}/modules"
mkdir -p "${ART}/sukisu"

cp "${OUT}/arch/arm64/boot/Image" \
    "${ART}/Image"

cp "${OUT}/.config" \
    "${ART}/kernel.config"

[ -f "${OUT}/System.map" ] &&
    cp "${OUT}/System.map" "${ART}/System.map"

[ -f "${OUT}/Module.symvers" ] &&
    cp "${OUT}/Module.symvers" "${ART}/Module.symvers"

[ -f "${OUT}/include/config/kernel.release" ] &&
    cp "${OUT}/include/config/kernel.release" \
       "${ART}/kernel.release"

# DTB / DTBO
if [ -d "${OUT}/arch/arm64/boot/dts" ]; then

    find "${OUT}/arch/arm64/boot/dts" \
        -type f \
        \( -name "*.dtb" -o -name "*.dtbo" \) \
        -exec cp --parents {} "${ART}/dtbs/" \;

fi

# Modules
find "${OUT}" \
    -type f \
    -name "*.ko" \
    -print0 |
while IFS= read -r -d '' ko; do

    rel="${ko#${OUT}/}"

    mkdir -p \
        "${ART}/modules/$(dirname "${rel}")"

    cp "${ko}" \
        "${ART}/modules/${rel}"

done

# ============================================================
# SUKISU METADATA
# ============================================================

echo "SukiSU Ultra builtin" \
    > "${ART}/sukisu/version"

echo "non-GKI manual hook" \
    > "${ART}/sukisu/hook"

if [ -d "${KERNEL_ROOT}/drivers/kernelsu/.git" ]; then

    git -C "${KERNEL_ROOT}/drivers/kernelsu" \
        rev-parse HEAD \
        > "${ART}/sukisu/commit"

else

    echo "builtin" \
        > "${ART}/sukisu/commit"

fi

grep -E \
    '^CONFIG_KSU=|^CONFIG_KSU_MANUAL_HOOK=|^CONFIG_KSU_KPROBES_KSUD=|^CONFIG_KSU_SUSFS=|^CONFIG_KPM=' \
    "${OUT}/.config" \
    > "${ART}/sukisu/config" || true

# ============================================================
# CHECK DTB
# ============================================================

DTB_COUNT="$(
    find "${OUT}/arch/arm64/boot/dts" \
        -type f \
        \( -name "*.dtb" -o -name "*.dtbo" \) \
        2>/dev/null |
    wc -l
)"

echo "${DTB_COUNT}" \
    > "${ART}/dtb.count"

# ============================================================
# SHA256
# ============================================================

(
    cd "${ART}"

    find . \
        -type f \
        ! -name "SHA256SUMS" \
        -print0 |
    sort -z |
    xargs -0 sha256sum \
        > SHA256SUMS
)

# ============================================================
# FINAL
# ============================================================

echo ""
echo "=================================================="
echo "SUKISU BUILD COMPLETE"
echo "=================================================="

echo ""
echo "Image:"
ls -lh "${ART}/Image"

echo ""
echo "DTB/DTBO:"
cat "${ART}/dtb.count"

echo ""
echo "SukiSU:"
cat "${ART}/sukisu/version"

echo ""
echo "Hook:"
cat "${ART}/sukisu/hook"

echo ""
echo "Artifacts:"
find "${ART}" -type f -printf '%P\n' | sort

echo ""
echo "=================================================="
echo "DONE"
echo "=================================================="
