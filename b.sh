#!/bin/bash
set -e

# ============================================================
# KERNELSU BACKSLASH v3.3.0-39 BUILD SCRIPT
# Target:
#   - Linux 4.14
#   - ARM64
#   - Non-GKI
#   - Spreadtrum / SharkL3
#   - Defconfig: a3core_eur_open_defconfig
# ============================================================

export KERNEL_ROOT="${GITHUB_WORKSPACE}"
export TOOLCHAIN_DIR="${KERNEL_ROOT}/toolchain_download"

export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-

export BSP_BUILD_FAMILY=sharkl3
export BSP_BUILD_ANDROID_OS=y

export DEFCONFIG="a3core_eur_open_defconfig"

# ============================================================
# KERNELSU VERSION
# ============================================================

export KSU_REPO="https://github.com/backslashxx/KernelSU.git"
# Mengambil dari env GitHub Actions jika ada, jika tidak default ke v3.3.0-39
export KSU_VERSION="${KSU_VERSION:-v3.3.0-39}"

cd "${KERNEL_ROOT}"

echo ""
echo "============================================================"
echo " KernelSU Backslash Builder"
echo "============================================================"
echo " KernelSU : ${KSU_VERSION}"
echo " Kernel   : Linux 4.14"
echo " Arch     : ${ARCH}"
echo " Defconfig: ${DEFCONFIG}"
echo "============================================================"
echo ""

# ============================================================
# CLEAN OLD BUILD OUTPUT
# ============================================================

echo "[+] Preparing workspace..."

rm -rf "${KERNEL_ROOT}/out"

mkdir -p "${KERNEL_ROOT}/output"
mkdir -p "${KERNEL_ROOT}/output_artifacts"

# ============================================================
# KERNELSU INTEGRATION
# ============================================================

echo ""
echo "============================================================"
echo "[+] Installing KernelSU ${KSU_VERSION}"
echo "============================================================"

cd "${KERNEL_ROOT}"

# Remove previous KernelSU integration if it exists.
if [ -d "${KERNEL_ROOT}/KernelSU" ]; then
    echo "[+] Removing old KernelSU checkout..."
    rm -rf "${KERNEL_ROOT}/KernelSU"
fi

# Remove old symlink if present.
if [ -L "${KERNEL_ROOT}/drivers/kernelsu" ]; then
    echo "[+] Removing old drivers/kernelsu symlink..."
    rm -f "${KERNEL_ROOT}/drivers/kernelsu"
fi

# Remove previous KSU Makefile entry if present.
if grep -q "obj-\$(CONFIG_KSU) += kernelsu/" \
    "${KERNEL_ROOT}/drivers/Makefile" 2>/dev/null; then

    echo "[+] Removing old KernelSU Makefile entry..."

    sed -i '/obj-\$(CONFIG_KSU) += kernelsu\//d' \
        "${KERNEL_ROOT}/drivers/Makefile"
fi

# Remove previous KSU Kconfig entry if present.
if grep -q 'source "drivers/kernelsu/Kconfig"' \
    "${KERNEL_ROOT}/drivers/Kconfig" 2>/dev/null; then

    echo "[+] Removing old KernelSU Kconfig entry..."

    sed -i '/source "drivers\/kernelsu\/Kconfig"/d' \
        "${KERNEL_ROOT}/drivers/Kconfig"
fi

# ------------------------------------------------------------
# Use Backslash setup.sh with dynamic KSU_VERSION tag
# ------------------------------------------------------------

echo "[+] Running Backslash KernelSU setup..."

curl -fL --retry 3 --retry-delay 2 \
    "https://raw.githubusercontent.com/backslashxx/KernelSU/${KSU_VERSION}/kernel/setup.sh" \
    -o /tmp/kernelsu-setup.sh

chmod +x /tmp/kernelsu-setup.sh

bash /tmp/kernelsu-setup.sh "${KSU_VERSION}"

# ============================================================
# VERIFY KERNELSU CHECKOUT
# ============================================================

echo ""
echo "============================================================"
echo "[+] Verifying KernelSU checkout"
echo "============================================================"

cd "${KERNEL_ROOT}/KernelSU"

ACTUAL_KSU_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
ACTUAL_KSU_COMMIT="$(git rev-parse HEAD)"

echo "Expected tag : ${KSU_VERSION}"
echo "Actual tag   : ${ACTUAL_KSU_TAG}"
echo "Commit       : ${ACTUAL_KSU_COMMIT}"

if [ "${ACTUAL_KSU_TAG}" != "${KSU_VERSION}" ]; then
    echo ""
    echo "[ERROR] KernelSU tag mismatch!"
    echo "Expected: ${KSU_VERSION}"
    echo "Actual  : ${ACTUAL_KSU_TAG}"
    exit 1
fi

echo "[OK] KernelSU tag verified."

# ============================================================
# VERIFY KSU VERSION SOURCE
# ============================================================

echo ""
echo "============================================================"
echo "[+] KernelSU source verification"
echo "============================================================"

KSU_VERSION_SOURCE=""

if [ -f "${KERNEL_ROOT}/KernelSU/kernel/Kconfig" ]; then
    KSU_VERSION_SOURCE="$(
        grep -E \
        'default[[:space:]]+[0-9]+' \
        "${KERNEL_ROOT}/KernelSU/kernel/Kconfig" \
        | head -n 5 || true
    )"
fi

echo "${KSU_VERSION_SOURCE}"

# ============================================================
# VERIFY UAPI v4
# ============================================================

echo ""
echo "============================================================"
echo "[+] Verifying KernelSU UAPI"
echo "============================================================"

KSU_UAPI_FILE="${KERNEL_ROOT}/KernelSU/uapi/supercall.h"

if [ ! -f "${KSU_UAPI_FILE}" ]; then
    echo "[ERROR] KernelSU UAPI header not found:"
    echo "${KSU_UAPI_FILE}"
    exit 1
fi

echo ""
echo "UAPI declaration:"
grep -n "KERNEL_SU_UAPI_VERSION" \
    "${KSU_UAPI_FILE}" || true

echo ""
echo "UAPI comments:"
grep -n "UAPI" \
    "${KSU_UAPI_FILE}" | head -20 || true

# Extract actual numeric UAPI version.
KSU_UAPI_VERSION="$(
    sed -n \
    's/.*KERNEL_SU_UAPI_VERSION[[:space:]]*=[[:space:]]*\([0-9]\+\).*/\1/p' \
    "${KSU_UAPI_FILE}" \
    | head -n 1
)"

echo ""
echo "Detected UAPI version: ${KSU_UAPI_VERSION}"

if [ "${KSU_UAPI_VERSION}" != "4" ]; then
    echo ""
    echo "[ERROR] KernelSU UAPI v4 was NOT detected!"
    echo "Detected: ${KSU_UAPI_VERSION}"
    exit 1
fi

echo "[OK] KernelSU UAPI v4 verified."

# ============================================================
# VERIFY KSU DRIVER LINK
# ============================================================

echo ""
echo "============================================================"
echo "[+] Verifying KernelSU driver integration"
echo "============================================================"

if [ ! -L "${KERNEL_ROOT}/drivers/kernelsu" ]; then
    echo "[ERROR] drivers/kernelsu symlink does not exist."
    exit 1
fi

echo "drivers/kernelsu -> $(readlink "${KERNEL_ROOT}/drivers/kernelsu")"

if [ ! -f "${KERNEL_ROOT}/drivers/kernelsu/Kconfig" ]; then
    echo "[ERROR] KernelSU Kconfig missing."
    exit 1
fi

if [ ! -f "${KERNEL_ROOT}/drivers/kernelsu/Makefile" ]; then
    echo "[ERROR] KernelSU Makefile missing."
    exit 1
fi

echo "[OK] KernelSU driver linked."

# ============================================================
# EXTRACT SOUND COMPONENT
# ============================================================

echo ""
echo "============================================================"
echo "[+] Extracting sound/soc/sprd"
echo "============================================================"

cd "${KERNEL_ROOT}"

if [ -d "${KERNEL_ROOT}/sound/soc/sprd" ]; then

    rm -rf "${KERNEL_ROOT}/output/sprd"

    cp -r \
        "${KERNEL_ROOT}/sound/soc/sprd" \
        "${KERNEL_ROOT}/output/"

    cd "${KERNEL_ROOT}/output"

    rm -f sprd.zip

    zip -r sprd.zip sprd

    cd "${KERNEL_ROOT}"

    echo "[OK] sprd.zip created."

else

    echo "[!] sound/soc/sprd not found."
    echo "[!] Skipping sound extraction."

fi

# ============================================================
# TOOLCHAIN SETUP
# ============================================================

echo ""
echo "============================================================"
echo "[+] Setting up toolchains"
echo "============================================================"

mkdir -p \
    "${TOOLCHAIN_DIR}/gcc-14.3" \
    "${TOOLCHAIN_DIR}/clang-r383902b"

# ------------------------------------------------------------
# Clang
# ------------------------------------------------------------

if [ ! -f \
    "${TOOLCHAIN_DIR}/clang-r383902b/bin/clang" ]; then

    echo "[+] Downloading Clang r383902b..."

    wget -q \
        "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/0e9e7035bf8ad42437c6156e5950eab13655b26c/clang-r383902b.tar.gz" \
        -O /tmp/clang.tar.gz

    tar -xf \
        /tmp/clang.tar.gz \
        -C "${TOOLCHAIN_DIR}/clang-r383902b"

    rm -f /tmp/clang.tar.gz

else

    echo "[=] Clang already exists."

fi

# ------------------------------------------------------------
# GCC
# ------------------------------------------------------------

if [ ! -f \
    "${TOOLCHAIN_DIR}/gcc-14.3/bin/aarch64-none-linux-gnu-gcc" ]; then

    echo "[+] Downloading GCC 14.3..."

    wget -q \
        "https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz" \
        -O /tmp/gcc.tar.xz

    tar -xf \
        /tmp/gcc.tar.xz \
        -C "${TOOLCHAIN_DIR}/gcc-14.3" \
        --strip-components=1

    rm -f /tmp/gcc.tar.xz

else

    echo "[=] GCC 14.3 already exists."

fi

# ============================================================
# TOOLCHAIN PATH
# ============================================================

export PATH="${TOOLCHAIN_DIR}/clang-r383902b/bin:${TOOLCHAIN_DIR}/gcc-14.3/bin:${PATH}"

export CROSS_COMPILE="${TOOLCHAIN_DIR}/gcc-14.3/bin/aarch64-none-linux-gnu-"

export CROSS_COMPILE_ARM32="${TOOLCHAIN_DIR}/gcc-14.3/bin/arm-none-linux-gnueabihf-"

echo ""
echo "============================================================"
echo "[+] Toolchain versions"
echo "============================================================"

echo ""
echo "Clang:"
clang --version | head -n 3

echo ""
echo "GCC:"
aarch64-none-linux-gnu-gcc --version | head -n 2

echo ""
echo "LLVM:"
ld.lld --version | head -n 2

# ============================================================
# DEFCONFIG
# ============================================================

echo ""
echo "============================================================"
echo "[+] Preparing kernel defconfig"
echo "============================================================"

cd "${KERNEL_ROOT}"

make \
    -C "${KERNEL_ROOT}" \
    O="${KERNEL_ROOT}/out" \
    ARCH="${ARCH}" \
    CC="${CC}" \
    LD=ld.lld \
    "${DEFCONFIG}"

echo ""
echo "[+] Defconfig generated."

# ============================================================
# FORCE KSU CONFIG
# ============================================================

echo ""
echo "============================================================"
echo "[+] Verifying/enabling KernelSU configuration"
echo "============================================================"

# KernelSU must be enabled.
if grep -q '^CONFIG_KSU=y' "${KERNEL_ROOT}/out/.config"; then

    echo "[OK] CONFIG_KSU=y already enabled."

else

    echo "[+] CONFIG_KSU=y not enabled by defconfig."
    echo "[+] Enabling CONFIG_KSU..."

    if [ -x "${KERNEL_ROOT}/scripts/config" ]; then

        "${KERNEL_ROOT}/scripts/config" \
            --file "${KERNEL_ROOT}/out/.config" \
            --enable CONFIG_KSU

    else

        echo "CONFIG_KSU=y" >> "${KERNEL_ROOT}/out/.config"

    fi

fi

# Normalize config.
make \
    -C "${KERNEL_ROOT}" \
    O="${KERNEL_ROOT}/out" \
    ARCH="${ARCH}" \
    olddefconfig

echo ""
echo "CONFIG_KSU:"
grep -n '^CONFIG_KSU' \
    "${KERNEL_ROOT}/out/.config" || true

if ! grep -q '^CONFIG_KSU=y' \
    "${KERNEL_ROOT}/out/.config"; then

    echo "[ERROR] CONFIG_KSU=y is not enabled."
    exit 1

fi

echo "[OK] CONFIG_KSU=y"

# ============================================================
# BUILD FLAGS
# ============================================================

export KBUILD_BUILD_USER="Xsanzz"
export KBUILD_BUILD_HOST="A03Core"

export KBUILD_BUILD_TIMESTAMP="$(
    date '+%a %b %d %T WIB %Y'
)"

export KCFLAGS="-march=armv8.2-a+crypto -mtune=cortex-a55 -fno-semantic-interposition"

export KBUILD_LDFLAGS="--gc-sections --icf=all"

# ============================================================
# DTC LIBYAML WORKAROUND
# ============================================================

echo ""
echo "============================================================"
echo "[+] Applying DTC workaround"
echo "============================================================"

# Keep your existing workaround for this old 4.14 tree.

sed -i '/yamltree.o/d' \
    "${KERNEL_ROOT}/scripts/dtc/Makefile"

sed -i '/dt_to_yaml/d' \
    "${KERNEL_ROOT}/scripts/dtc/dtc.c"

# Avoid duplicate HOSTLOADLIBES_dtc entries.
if ! grep -q \
    'HOSTLOADLIBES_dtc.*-lyaml' \
    "${KERNEL_ROOT}/scripts/dtc/Makefile"; then

    cat >> "${KERNEL_ROOT}/scripts/dtc/Makefile" <<'EOF'

# KernelSU / old 4.14 DTC libyaml compatibility
HOSTLOADLIBES_dtc := -lyaml
EOF

fi

# ============================================================
# BUILD KERNEL IMAGE
# ============================================================

echo ""
echo "============================================================"
echo "[+] BUILDING KERNEL IMAGE"
echo "============================================================"
echo ""

START_TIME="$(date +%s)"

make \
    -C "${KERNEL_ROOT}" \
    O="${KERNEL_ROOT}/out" \
    -j"$(nproc)" \
    ARCH="${ARCH}" \
    CC="${CC}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
    CLANG_TRIPLE="${CLANG_TRIPLE}" \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    KCFLAGS="${KCFLAGS}" \
    KBUILD_LDFLAGS="${KBUILD_LDFLAGS}" \
    Image

END_TIME="$(date +%s)"

BUILD_TIME=$((END_TIME - START_TIME))

echo ""
echo "============================================================"
echo "[OK] Kernel Image build finished"
echo "Build time: ${BUILD_TIME} seconds"
echo "============================================================"

# ============================================================
# VERIFY IMAGE
# ============================================================

IMAGE="${KERNEL_ROOT}/out/arch/arm64/boot/Image"

if [ ! -f "${IMAGE}" ]; then

    echo "[ERROR] Image was not generated."

    exit 1

fi

echo ""
echo "[+] Kernel Image:"
ls -lh "${IMAGE}"

# ============================================================
# BUILD MODULES
# ============================================================

echo ""
echo "============================================================"
echo "[+] BUILDING KERNEL MODULES"
echo "============================================================"

make \
    -C "${KERNEL_ROOT}" \
    O="${KERNEL_ROOT}/out" \
    -j"$(nproc)" \
    ARCH="${ARCH}" \
    CC="${CC}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
    CLANG_TRIPLE="${CLANG_TRIPLE}" \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    KCFLAGS="${KCFLAGS}" \
    KBUILD_LDFLAGS="${KBUILD_LDFLAGS}" \
    modules

echo ""
echo "[+] Number of kernel modules:"

find "${KERNEL_ROOT}/out" \
    -type f \
    -name "*.ko" \
    | wc -l

# ============================================================
# OPTIONAL DTBS
# ============================================================

echo ""
echo "============================================================"
echo "[+] BUILDING DTBS"
echo "============================================================"

make \
    -C "${KERNEL_ROOT}" \
    O="${KERNEL_ROOT}/out" \
    -j"$(nproc)" \
    ARCH="${ARCH}" \
    CC="${CC}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
    CLANG_TRIPLE="${CLANG_TRIPLE}" \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    BSP_BUILD_FAMILY="${BSP_BUILD_FAMILY}" \
    BSP_BUILD_ANDROID_OS="${BSP_BUILD_ANDROID_OS}" \
    dtbs || {

    echo ""
    echo "[!] DTBS target failed."
    echo "[!] Kernel Image/modules remain available."
    echo "[!] Continuing artifact collection."

}

# ============================================================
# ARTIFACT COLLECTION
# ============================================================

echo ""
echo "============================================================"
echo "[+] COLLECTING ARTIFACTS"
echo "============================================================"

ART="${GITHUB_WORKSPACE}/output_artifacts"
OUT="${KERNEL_ROOT}/out"

rm -rf "${ART}"

mkdir -p "${ART}"
mkdir -p "${ART}/modules"
mkdir -p "${ART}/dtbs"

# ------------------------------------------------------------
# Kernel Image
# ------------------------------------------------------------

if [ -f "${OUT}/arch/arm64/boot/Image" ]; then

    cp \
        "${OUT}/arch/arm64/boot/Image" \
        "${ART}/Image"

    echo "[+] Image"

fi

# ------------------------------------------------------------
# Kernel config
# ------------------------------------------------------------

if [ -f "${OUT}/.config" ]; then

    cp \
        "${OUT}/.config" \
        "${ART}/kernel.config"

    echo "[+] kernel.config"

fi

# ------------------------------------------------------------
# System.map
# ------------------------------------------------------------

if [ -f "${OUT}/System.map" ]; then

    cp \
        "${OUT}/System.map" \
        "${ART}/System.map"

    echo "[+] System.map"

fi

# ------------------------------------------------------------
# Module.symvers
# ------------------------------------------------------------

if [ -f "${OUT}/Module.symvers" ]; then

    cp \
        "${OUT}/Module.symvers" \
        "${ART}/Module.symvers"

    echo "[+] Module.symvers"

fi

# ------------------------------------------------------------
# Kernel release
# ------------------------------------------------------------

if [ -f "${OUT}/include/config/kernel.release" ]; then

    cp \
        "${OUT}/include/config/kernel.release" \
        "${ART}/kernel.release"

    echo "[+] kernel.release"

fi

# ------------------------------------------------------------
# KernelSU source metadata
# ------------------------------------------------------------

echo "${KSU_VERSION}" \
    > "${ART}/kernelsu.version"

echo "${ACTUAL_KSU_COMMIT}" \
    > "${ART}/kernelsu.commit"

echo "${KSU_UAPI_VERSION}" \
    > "${ART}/kernelsu.uapi"

# ------------------------------------------------------------
# KernelSU UAPI header
# ------------------------------------------------------------

mkdir -p "${ART}/kernelsu-uapi"

cp \
    "${KSU_UAPI_FILE}" \
    "${ART}/kernelsu-uapi/supercall.h"

# ------------------------------------------------------------
# KernelSU Kconfig / Makefile
# ------------------------------------------------------------

cp \
    "${KERNEL_ROOT}/KernelSU/kernel/Kconfig" \
    "${ART}/kernelsu-uapi/Kconfig"

cp \
    "${KERNEL_ROOT}/KernelSU/kernel/Makefile" \
    "${ART}/kernelsu-uapi/Makefile"

# ------------------------------------------------------------
# Kernel modules
# ------------------------------------------------------------

echo ""
echo "[+] Collecting .ko files..."

find "${OUT}" \
    -type f \
    -name "*.ko" \
    | while read -r ko; do

        rel="${ko#${OUT}/}"

        mkdir -p \
            "${ART}/modules/$(dirname "${rel}")"

        cp \
            "${ko}" \
            "${ART}/modules/${rel}"

    done

# ------------------------------------------------------------
# DTB / DTBO
# ------------------------------------------------------------

echo ""
echo "[+] Collecting DTB / DTBO..."

find "${OUT}/arch/arm64/boot/dts" \
    -type f \
    \( -name "*.dtb" -o -name "*.dtbo" \) \
    2>/dev/null \
    | while read -r dtb; do

        rel="${dtb#${OUT}/arch/arm64/boot/dts/}"

        mkdir -p \
            "${ART}/dtbs/$(dirname "${rel}")"

        cp \
            "${dtb}" \
            "${ART}/dtbs/${rel}"

    done

# ============================================================
# BUILD SUMMARY
# ============================================================

echo ""
echo "============================================================"
echo " BUILD SUMMARY"
echo "============================================================"

echo ""
echo "KernelSU:"
echo "  Version : ${KSU_VERSION}"
echo "  Commit  : ${ACTUAL_KSU_COMMIT}"
echo "  UAPI    : v${KSU_UAPI_VERSION}"

echo ""
echo "Kernel:"
grep -E \
    '^VERSION|^PATCHLEVEL|^SUBLEVEL|^EXTRAVERSION' \
    "${KERNEL_ROOT}/Makefile"

echo ""
echo "Config:"
grep '^CONFIG_KSU' \
    "${OUT}/.config" || true

echo ""
echo "Image:"
ls -lh \
    "${ART}/Image"

echo ""
echo "Modules:"
find "${ART}/modules" \
    -type f \
    -name "*.ko" \
    | wc -l

echo ""
echo "DTB/DTBO:"
find "${ART}/dtbs" \
    -type f \
    | wc -l

# ============================================================
# CHECKSUMS
# ============================================================

echo ""
echo "============================================================"
echo "[+] Generating SHA256SUMS"
echo "============================================================"

cd "${ART}"

find . \
    -type f \
    ! -name "SHA256SUMS" \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    > SHA256SUMS

echo ""
cat SHA256SUMS

# ============================================================
# FINAL ARTIFACT LIST
# ============================================================

echo ""
echo "============================================================"
echo " FINAL ARTIFACTS"
echo "============================================================"

find "${ART}" \
    -type f \
    -exec du -h {} \; \
    | sort

echo ""
echo "============================================================"
echo "[SUCCESS] Kernel build completed."
echo "============================================================"
