#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds PSL from sources.

PSL_TAR=libpsl-0.19.1.tar.gz
PSL_DIR=libpsl-0.19.1
PKG_NAME=libpsl

# Avoid shellcheck.net warning
CURR_DIR="$PWD"

# Sets the number of make jobs if not set in environment
: "${MAKE_JOBS:=4}"

###############################################################################

# Get the environment as needed. We can't export it because it includes arrays.
if ! source ./build-environ.sh
then
    echo "Failed to set environment"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

CA_ZOO="$HOME/.cacert/cacert.pem"
if [[ ! -f "$CA_ZOO" ]]; then
    echo "PSL requires several CA roots. Please run build-cacert.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ -e "$INSTX_CACHE/$PKG_NAME" ]]; then
    # Already installed, return success
    echo ""
    echo "$PKG_NAME is already installed."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
fi

# Get a sudo password as needed. The password should die when this
# subshell goes out of scope.
if [[ -z "$SUDO_PASSWORD" ]]; then
    source ./build-password.sh
fi

###############################################################################

if ! ./build-iconv.sh
then
    echo "Failed to build iConv"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

###############################################################################

if ! ./build-unistr.sh
then
    echo "Failed to build Unistring"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

###############################################################################

if ! ./build-idn.sh
then
    echo "Failed to build IDN"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

###############################################################################

echo
echo "********** libpsl **********"
echo

# This fails when Wget < 1.14
echo "Attempting download PSL using HTTPS."
wget --ca-certificate="$CA_ZOO" "https://github.com/rockdaboot/libpsl/releases/download/$PSL_DIR/$PSL_TAR" -O "$PSL_TAR"

# Download over insecure channel
if [[ "$?" -ne "0" ]]; then
    echo "Attempting download PSL using insecure channel."
    wget --no-check-certificate "https://github.com/rockdaboot/libpsl/releases/download/$PSL_DIR/$PSL_TAR" -O "$PSL_TAR"
fi

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download libpsl"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$PSL_DIR" &>/dev/null
gzip -d < "$PSL_TAR" | tar xf -
cd "$PSL_DIR"

# Avoid reconfiguring.
if [[ ! -e "configure" ]]; then
    autoreconf --force --install
    if [[ "$?" -ne "0" ]]; then
        echo "Failed to reconfigure libpsl"
        [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
    fi
fi

# http://pkgs.fedoraproject.org/cgit/rpms/gnutls.git/tree/gnutls.spec; thanks NM.
# AIX needs the execute bit reset on the file.
sed -e 's|sys_lib_dlsearch_path_spec="/lib /usr/lib|sys_lib_dlsearch_path_spec="/lib %{_libdir} /usr/lib|g' configure > configure.fixed
mv configure.fixed configure; chmod +x configure

    PKG_CONFIG_PATH="${BUILD_PKGCONFIG[*]}" \
    CPPFLAGS="${BUILD_CPPFLAGS[*]}" \
    CFLAGS="${BUILD_CFLAGS[*]}" \
    CXXFLAGS="${BUILD_CXXFLAGS[*]}" \
    LDFLAGS="${BUILD_LDFLAGS[*]}" \
    LIBS="${BUILD_LIBS[*]}" \
./configure --enable-shared --prefix="$INSTX_PREFIX" --libdir="$INSTX_LIBDIR" \
    --enable-runtime=libidn2 \
    --enable-builtin=libidn2 \
    --with-libiconv-prefix="$INSTX_PREFIX" \
    --with-libintl-prefix="$INSTX_PREFIX"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure libpsl"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

# Update the PSL data file
echo "Updating Public Suffix List (PSL) data file"
mkdir -p list
wget --ca-certificate="$CA_ZOO" https://raw.githubusercontent.com/publicsuffix/list/master/public_suffix_list.dat -O list/public_suffix_list.dat

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download Public Suffix List (PSL)"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("-j" "$MAKE_JOBS")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build libpsl"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

# libpsl is failing its self tests at the moment
# https://github.com/rockdaboot/libpsl/issues/87
# MAKE_FLAGS=("check")
# if ! "$MAKE" "${MAKE_FLAGS[@]}"
# then
#    echo "Failed to test libpsl"
#    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
# fi

MAKE_FLAGS=("install")
if [[ ! (-z "$SUDO_PASSWORD") ]]; then
    echo "$SUDO_PASSWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

# Set package status to installed. Delete the file to rebuild the package.
touch "$INSTX_CACHE/$PKG_NAME"

###############################################################################

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$PSL_TAR" "$PSL_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-libpsl.sh 2>&1 | tee build-libpsl.log
    if [[ -e build-libpsl.log ]]; then
        rm -f build-libpsl.log
    fi
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
