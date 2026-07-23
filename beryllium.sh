#!/bin/bash
set -e
echo
echo "Issue Build Commands"
echo

# ---- Parse args (dipanggil dari workflow, satu variant per run - gaya build_kernel_docker_quick.sh) ----
VARIANT="9.1.24-SE"
KSU="Exclude"
JOBS="24"
CLANG_PATH_ARG=""
DEFCONFIG="nogravity_defconfig"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --ksu) KSU="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --clang-path) CLANG_PATH_ARG="$2"; shift 2 ;;
        --defconfig) DEFCONFIG="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; shift ;;
    esac
done

case "${VARIANT}" in
    9.1.24-SE|9.1.24-NSE) FW_VER="9.1.24" ;;
    10.3.7-SE|10.3.7-NSE) FW_VER="10.3.7" ;;
    *) echo "Unknown variant: ${VARIANT}"; exit 1 ;;
esac
case "${VARIANT}" in
    *-SE)  TOUCH_DTS="SE"  ;;
    *-NSE) TOUCH_DTS="NSE" ;;
esac

PHONE="beryllium"

mkdir -p out
echo 0 > ./out/.version
export ARCH=arm64
export SUBARCH=arm64
export CLANG_PATH="${CLANG_PATH_ARG:-$HOME/toolchains/proton-clang/bin}"
export PATH="${CLANG_PATH}:${PATH}"
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export KBUILD_BUILD_USER=Pierre2324
export KBUILD_BUILD_HOST=bokir
export KBUILD_BUILD_TIMESTAMP="Sun, 27 Dec 2020 18:30:00 +0700"
export SOURCE_DATE_EPOCH=1609500600


echo
echo "Set DEFCONFIG"
echo

# Setup source driver KernelSU-Next (mode legacy = manual hook, cocok dengan
# hook manual yang sudah dipatch di security.c/fs/exec.c/dll). Harus jalan
# sebelum "make defconfig" karena nambah entry ke drivers/Kconfig & drivers/Makefile.
# Setup KernelSU
if [ "${KSU}" = "Include" ]; then
    if ! curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy; then
        echo "KernelSU setup failed"
        exit 1
    fi

    echo "Downloading KSU defconfig..."

    if ! curl -fL \
        https://raw.githubusercontent.com/Shiki-ghub/Ajs/main/nogravityxxksu_defconfig \
        -o arch/arm64/configs/${DEFCONFIG}; then
        echo "Failed to download KSU defconfig"
        exit 1
    fi
fi

make CC=clang \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    O=out \
    ARCH=${ARCH} \
    LOCALVERSION=${LOCALVERSION} \
    ${DEFCONFIG}

# Toggle CONFIG_KSU sesuai input
if [ "${KSU}" = "Include" ]; then
    ./scripts/config --file out/.config --enable CONFIG_KSU
else
    ./scripts/config --file out/.config --disable CONFIG_KSU
fi
make CC=clang \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    O=out \
    ARCH=${ARCH} \
    LOCALVERSION=${LOCALVERSION} \
    olddefconfig

echo
echo "Apply touch firmware / dts overlay for ${VARIANT}"
echo
cp firmware/touch_fw_variant/${FW_VER}/* firmware/
cp arch/arm64/boot/dts/qcom/SE_NSE/${TOUCH_DTS}/* arch/arm64/boot/dts/qcom/

echo
echo "Build The Good Stuff"
echo
make CC=clang AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip O=out ARCH=${ARCH} LOCALVERSION=${LOCALVERSION} -j${JOBS}

echo "Build succesful"

mkdir -p ./release/${PHONE}

# Copy the current Image.gz-dtb to history with incremented name
history_dir=./release/${PHONE}/history-${VARIANT}
mkdir -p "$history_dir"
current_file=./release/${PHONE}/Image-${VARIANT}.gz-dtb
if [ -f "$current_file" ]; then
    n=$(ls "$history_dir" | grep -oP "^Image-${VARIANT}\K\d+$" | sort -nr | head -n1)
    n=$((n + 1))
    cp -f "$current_file" "$history_dir/Image-${VARIANT}${n}.gz-dtb"
fi

# Copy the new build to the release directory
cp -f ./out/arch/arm64/boot/Image.gz-dtb ./release/${PHONE}/Image-${VARIANT}.gz-dtb
