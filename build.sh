#!/bin/bash

set -e

DEFCONFIG=${1:-nogravity_defconfig}
KERNEL_DIR=${2:-$(pwd)}
PROTON_DIR=${3:-$HOME/proton-clang}
ANYKERNEL_DIR=${4:-$HOME/AnyKernel3}
PHONE=${5:-beryllium}
KSU_ENABLED=${KSU_ENABLED:-N}

JOBS=$(nproc --all)
OUT_DIR="$KERNEL_DIR/out"
BUILD_LOG="$OUT_DIR/build.log"
OUTPUT_BASE="$OUT_DIR/outputs/$PHONE"

mkdir -p "$OUT_DIR"
mkdir -p "$OUTPUT_BASE/NSE"
touch "$BUILD_LOG"

export PATH="$PROTON_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CC="clang"
export CXX="clang++"
export HOSTCC="clang"
export HOSTCXX="clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export STRIP="llvm-strip"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-builder}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-proton-build}

export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_DIR="$HOME/.ccache"
ccache -M 10G >/dev/null 2>&1

cd "$KERNEL_DIR"

# Patch gold
find . -name "Makefile" -type f | while read mf; do
    if grep -q "fuse-ld=gold" "$mf" 2>/dev/null; then
        sed -i 's/-fuse-ld=gold//g' "$mf"
    fi
done

# ============================================
# BUILD FUNCTIONS
# ============================================
Build() {
    make -j"$JOBS" O="$OUT_DIR" \
        ARCH=arm64 CC="$CC" CXX="$CXX" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" \
        CROSS_COMPILE="$CROSS_COMPILE" CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
        2>&1 | tee -a "$BUILD_LOG"
    return ${PIPESTATUS[0]}
}

Build_lld() {
    make -j"$JOBS" O="$OUT_DIR" \
        ARCH=arm64 CC="$CC" CXX="$CXX" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        AR="$AR" NM="$NM" LD="$LINKER" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" \
        CROSS_COMPILE="$CROSS_COMPILE" CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
        2>&1 | tee -a "$BUILD_LOG"
    return ${PIPESTATUS[0]}
}

Package() {
    local VARIANT=$1
    if [ -d "$ANYKERNEL_DIR" ]; then
        cd "$ANYKERNEL_DIR"
        rm -f Image* *.dtb dtbo.img
        if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
            cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" .
        elif [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
            cp "$OUT_DIR/arch/arm64/boot/Image.gz" .
        elif [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
            cp "$OUT_DIR/arch/arm64/boot/Image" .
        fi
        local DTB_DIR="$OUT_DIR/arch/arm64/boot/dts/qcom"
        ls "$DTB_DIR"/*.dtb 1>/dev/null 2>&1 && cp "$DTB_DIR"/*.dtb .
        [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ] && cp "$OUT_DIR/arch/arm64/boot/dtbo.img" .
        sed -i "s/^device.name1=.*/device.name1=$PHONE/" anykernel.sh 2>/dev/null || true
        
        local ZIP_NAME="ProtonKernel-${PHONE}-${VARIANT}-$(date +%Y%m%d-%H%M).zip"
        [ "$KSU_ENABLED" = "Y" ] && ZIP_NAME="ProtonKernel-${PHONE}-${VARIANT}-KSU-$(date +%Y%m%d-%H%M).zip"
        
        zip -r9 "$OUT_DIR/$ZIP_NAME" * -x .git README.md *placeholder .gitignore >/dev/null
        echo "✓ Packaged: $ZIP_NAME"
        cd "$KERNEL_DIR"
    fi
}

# ============================================
# GENERATE CONFIG & BUILD NSE
# ============================================
echo ""
echo "========================================"
echo "  Generating kernel config..."
echo "========================================"
make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG"

echo ""
echo "========================================"
echo "  Building NSE..."
echo "========================================"

cp -f arch/arm64/boot/dts/qcom/SE_NSE/NSE/* arch/arm64/boot/dts/qcom/ 2>/dev/null || true
[ -d "firmware/touch_fw_variant/NSE" ] && cp -f firmware/touch_fw_variant/NSE/* firmware/ 2>/dev/null || true
[ -d "firmware/touch_fw_variant/9.1.24-NSE" ] && cp -f firmware/touch_fw_variant/9.1.24-NSE/* firmware/ 2>/dev/null || true

if [ -z "${LINKER}" ]; then
    Build
else
    Build_lld
fi

if [ $? -ne 0 ]; then
    echo "❌ Build failed: NSE"
    rm -rf "$OUTPUT_BASE/NSE"/*
    exit 1
else
    echo "✅ Build successful: NSE"
    cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$OUTPUT_BASE/NSE/" 2>/dev/null || \
    cp "$OUT_DIR/arch/arm64/boot/Image.gz" "$OUTPUT_BASE/NSE/" 2>/dev/null || \
    cp "$OUT_DIR/arch/arm64/boot/Image" "$OUTPUT_BASE/NSE/" 2>/dev/null || true
    Package "NSE"
fi

echo ""
echo "========================================"
echo "  BUILD COMPLETE!"
echo "========================================"
echo "  Device : $PHONE"
echo "  KSU    : $KSU_ENABLED"
echo "  Output : $OUTPUT_BASE"
echo "========================================"
