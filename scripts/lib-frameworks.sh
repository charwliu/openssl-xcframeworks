#!/bin/bash

#—————————————————————————————————————————————————————————————————————————————————————————
# Output help information.
#—————————————————————————————————————————————————————————————————————————————————————————
echo_help() {
  cat <<HEREDOC
Usage: $0 [options...] static|dynamic
Options
     --directory=DIRECTORY         Specify the root build directory where libssl was built. The
                                   default is the script directory.
     --frameworks=DIRECTORY        Specify the directory name to output the finished frameworks,
                                   relative to the root build directory. Default is "frameworks".
Commands
     static                      Build an XCFramework meant for static linking.
     dynamic                     Build an XCFramework meant for dynamic linking.

The command specified above will build the specified library type based on the targets that were
built with the "build-openssl.sh" script, which must be used first in order to build the object
files.

HEREDOC
}

# Inspect Mach-O load commands to get minimum SDK version.
#
# Depending on the actual minimum SDK version it may look like this
# (for modern SDKs):
#
#     Load command 1
#            cmd LC_BUILD_VERSION
#        cmdsize 24
#       platform 8
#            sdk 13.2                   <-- target SDK
#          minos 12.0                   <-- minimum SDK
#         ntools 0
#
# Or like this for older versions, with a platform-dependent tag:
#
#     Load command 1
#           cmd LC_VERSION_MIN_WATCHOS
#       cmdsize 16
#       version 4.0                     <-- minimum SDK
#           sdk 6.1                     <-- target SDK
function get_min_sdk() {
    local file=$1
    set +o pipefail
    otool -l "$file" | awk "
        /^Load command/ {
            last_command = \"\"
        }
        \$1 == \"cmd\" {
            last_command = \$2
        }
        (last_command ~ /LC_BUILD_VERSION/ && \$1 == \"minos\") ||
        (last_command ~ /^LC_VERSION_MIN_/ && \$1 == \"version\") {
            print \$2
            exit
        }
    "
    set -o pipefail
}

# Read OpenSSL version from opensslv.h file.
#
# In modern OpenSSL releases the version line looks like this:
#
#     # define OPENSSL_VERSION_TEXT    "OpenSSL 1.1.1g  21 Apr 2020"
#
# But for older versions with FIPS module it may look like this:
#
#     # ifdef OPENSSL_FIPS
#     #  define OPENSSL_VERSION_TEXT    "OpenSSL 1.0.2u-fips  20 Dec 2019"
#     # else
#     #  define OPENSSL_VERSION_TEXT    "OpenSSL 1.0.2u  20 Dec 2019"
#     # endif
#
# For App Store validation purposes, replace trailing letter with
# 2-digit offset from 'a' (ASCII 97), plus 1 for 1-based
#
#   1.0.2u
#   'u' = 117 -> 20 + 1 = 21
#   1.0.221
#
#   1.1.1g
#   'g' = 103 -> 6 + 1 = 07 (zero-padded)
#   1.1.107
#
# Also, to allow multiple releases of the same OpenSSL packaging
# tack two extra version digits to the end using PACKAGE_VERSION:
#
#   1.1.10701
#
# This is what Debian might have called "1.1.1g-1".
function get_openssl_version() {
    local opensslv=$1
    local std_version=$(awk '/define OPENSSL_VERSION_TEXT/ && !/-fips/ {print $5}' "$opensslv")
    if [[ "$NORMALIZE_OPENSSL_VERSION" != "yes" ]]; then
        echo $std_version
        return
    fi
    local generic_version=${std_version%?}
    local subpatch=${std_version: -1}
    local subpatch_number=$(($(printf '%d' \'$subpatch) - 97 + 1))
    local normalized_version="${generic_version}$(printf '%02d' $subpatch_number)"
    local package_version="${normalized_version}$(printf '%02d' $PACKAGE_VERSION)"
    echo $package_version
}

#—————————————————————————————————————————————————————————————————————————————————————————
# check whether or not bitcode is present in a framework.
#   $1: Path to framework to check.
#—————————————————————————————————————————————————————————————————————————————————————————
function check_bitcode() {
    local FWDIR=$1

    if [[ $FWTYPE == "dynamic" ]]; then
   		BITCODE_PATTERN="__LLVM"
    else
    	BITCODE_PATTERN="__bitcode"
	fi

	if otool -l "$FWDIR/$FWNAME" | grep "${BITCODE_PATTERN}" >/dev/null; then
       		echo "INFO: $FWDIR contains Bitcode"
	else
        	echo "INFO: $FWDIR doesn't contain Bitcode"
	fi
}


#—————————————————————————————————————————————————————————————————————————————————————————
# make macos symlinks
#   $1: Path of the framework to check/fix.
#   $2: The system type from ALL_SYSTEMS of the framework.
#—————————————————————————————————————————————————————————————————————————————————————————
function make_mac_symlinks() {
    local SYSTYPE=$2
    if [[ $SYSTYPE == "MacOSX" ]]; then
		local FWDIR=$1
		local CURRENT=$(pwd)
		cd $FWDIR

		mkdir "Versions"
		mkdir "Versions/A"
		mkdir "Versions/A/Resources"
		mv "openssl" "Headers" "Versions/A"
		mv "Info.plist" "Versions/A/Resources"

		(cd "Versions" && ln -s "A" "Current")
		ln -s "Versions/Current/openssl"
		ln -s "Versions/Current/Headers"
		ln -s "Versions/Current/Resources"
	
		cd $CURRENT
	fi
}


function build_libraries() {
    DEVELOPER=`xcode-select -print-path`
    FW_EXEC_NAME="${FWNAME}.framework/${FWNAME}"
    INSTALL_NAME="@rpath/${FW_EXEC_NAME}"
    COMPAT_VERSION="1.0.0"
    CURRENT_VERSION="1.0.0"

    RX='([A-z]+)([0-9]+(\.[0-9]+)*)-([A-z0-9]+)\.sdk'

    cd $BUILD_DIR/bin

    #
    # build the individual dylibs
    #
    for TARGETDIR in `ls -d *.sdk`; do
        if [[ $TARGETDIR =~ $RX ]]; then
            PLATFORM="${BASH_REMATCH[1]}"
            SDKVERSION="${BASH_REMATCH[2]}"
            ARCH="${BASH_REMATCH[4]}"
        fi

        _platform="${PLATFORM}"
        if [[ "${PLATFORM}" == "Catalyst" ]]; then
          _platform="MacOSX"
        fi

        echo "Assembling .dylib for $PLATFORM $SDKVERSION ($ARCH)"

        MIN_SDK_VERSION=$(get_min_sdk "${TARGETDIR}/lib/libcrypto.a")

        if [[ $PLATFORM == AppleTVSimulator* ]]; then
            MIN_SDK="-tvos_simulator_version_min $MIN_SDK_VERSION"
        elif [[ $PLATFORM == AppleTV* ]]; then
            MIN_SDK="-tvos_version_min $MIN_SDK_VERSION"
        elif [[ $PLATFORM == MacOSX* ]]; then
            MIN_SDK="-macosx_version_min $MIN_SDK_VERSION"
        elif [[ $PLATFORM == Catalyst* ]]; then
            MIN_SDK="-platform_version mac-catalyst 13.0 $MIN_SDK_VERSION"
        elif [[ $PLATFORM == iPhoneSimulator* ]]; then
            MIN_SDK="-ios_simulator_version_min $MIN_SDK_VERSION"
        elif [[ $PLATFORM == WatchOS* ]]; then
            MIN_SDK="-watchos_version_min $MIN_SDK_VERSION"
        elif [[ $PLATFORM == WatchSimulator* ]]; then
            MIN_SDK="-watchos_simulator_version_min $MIN_SDK_VERSION"
        else
            MIN_SDK="-ios_version_min $MIN_SDK_VERSION"
        fi

        CROSS_TOP="${DEVELOPER}/Platforms/${_platform}.platform/Developer"
        CROSS_SDK="${_platform}${SDKVERSION}.sdk"
        SDK="${CROSS_TOP}/SDKs/${CROSS_SDK}"

        local ISBITCODE=""
        if otool -l "$TARGETDIR/lib/libcrypto.a" | grep "__bitcode" >/dev/null; then
            ISBITCODE="-bitcode_bundle"
        fi

        TARGETOBJ="${TARGETDIR}/obj"
        rm -rf $TARGETOBJ
        mkdir $TARGETOBJ
        cd $TARGETOBJ
        ar -x ../lib/libcrypto.a
        ar -x ../lib/libssl.a
        cd ..

        # libtool -static -no_warning_for_no_symbols -o ${FWNAME}.a lib/libcrypto.a lib/libssl.a

        # macOS frameworks have a bit different structure inside.
        if [[ $PLATFORM == MacOSX* ]]; then
            INSTALL_NAME="@rpath/${FWNAME}.framework/Versions/A/${FWNAME}"
        else
            INSTALL_NAME="@rpath/${FWNAME}.framework/${FWNAME}"
        fi

        ld obj/*.o \
            -dylib \
            $ISBITCODE \
            -lSystem \
            -arch $ARCH \
            $MIN_SDK \
            -syslibroot $SDK \
            -compatibility_version $COMPAT_VERSION \
            -current_version $CURRENT_VERSION \
            -application_extension \
            -install_name $INSTALL_NAME \
            -o $FWNAME.dylib

        rm -rf obj/
        cd ..
    done
    cd ..
}


#—————————————————————————————————————————————————————————————————————————————————————————
# build a dynamic framework given the list of targets.
#  $1: a list of targets or directory names for which to build a framework.
#  $2: The system type, needed when passing directory names.
#—————————————————————————————————————————————————————————————————————————————————————————
build_dynamic_framework() {
    local FWDIR="$1"
    local SYS="$2"
    local FILES=($3)

    echo -e "\nTargets:"
    for target in ${FILES[@]}; do
        if otool -l "$target" | grep "__LLVM" >/dev/null; then
            echo "   $target (contains bitcode)"
        else
            echo "   $target (without bitcode)"
        fi
    done


    if [[ ${#FILES[@]} -gt 0 && -e ${FILES[0]} ]]; then
        printf "Creating dynamic framework for $SYS ($(basename $(dirname $FWDIR)))..."
        mkdir -p $FWDIR/Headers/$FWNAME
        lipo -create ${FILES[@]} -output $FWDIR/$FWNAME
        cp -r include/$FWNAME/* $FWDIR/Headers/$FWNAME/
        cp -r $SCRIPTDIR/assets/openssl.h $FWDIR/Headers/
        cp -r $SCRIPTDIR/assets/module.modulemap $FWDIR/Headers/
        cp -L $SCRIPTDIR/assets/$SYS/Info.plist $FWDIR/Info.plist
        MIN_SDK_VERSION=$(get_min_sdk "$FWDIR/$FWNAME")
        OPENSSL_VERSION=$(get_openssl_version "$FWDIR/Headers/opensslv.h")
        sed -e "s/\\\$(MIN_SDK_VERSION)/$MIN_SDK_VERSION/g" \
            -e "s/\\\$(OPENSSL_VERSION)/$OPENSSL_VERSION/g" \
            -i '' "$FWDIR/Info.plist"
        echo -e " done:\n   $FWDIR"
        check_bitcode $FWDIR
        make_mac_symlinks $FWDIR $SYS
    else
        echo "Skipped framework for $SYS"
    fi
    rm -f ${FILES[@]}
}


#—————————————————————————————————————————————————————————————————————————————————————————
# build static frameworks given the list of targets.
#  $1: Output directory for the framework.
#  $2: System type of the framework.
#  $3: List of library files to embed in the framework.
#—————————————————————————————————————————————————————————————————————————————————————————
build_static_framework() {
    local FWDIR="$1"
    local SYS="$2"
    local LIBS_CRYPTO=($3)
    local LIBS_SSL=($4)

    echo -e "\nCreating static framework for $SYS"
    if [[ ${#LIBS_CRYPTO[@]} -gt 0 && -e ${LIBS_CRYPTO[0]} && ${#LIBS_SSL[@]} -gt 0 && -e ${LIBS_SSL[0]} ]]; then

        mkdir -p $FWDIR/lib

        lipo -create ${LIBS_CRYPTO[@]} -output $FWDIR/lib/libcrypto.a
        lipo -create ${LIBS_SSL[@]} -output $FWDIR/lib/libssl.a
        libtool -no_warning_for_no_symbols -static -o $FWDIR/$FWNAME $FWDIR/lib/*.a
        rm -rf $FWDIR/lib
        mkdir -p $FWDIR/Headers/$FWNAME
        mkdir -p $FWDIR/Modules
        cp -r include/$FWNAME/* $FWDIR/Headers/$FWNAME/
        cp -r $SCRIPTDIR/assets/openssl.h $FWDIR/Headers/
        cp -r $SCRIPTDIR/assets/module.modulemap $FWDIR/Modules/
        cp -L $SCRIPTDIR/assets/Info.plist $FWDIR/Info.plist
        MIN_SDK_VERSION=$(get_min_sdk "$FWDIR/$FWNAME")
        OPENSSL_VERSION=$(get_openssl_version "$FWDIR/Headers/opensslv.h")
        sed -e "s/\\\$(MIN_SDK_VERSION)/$MIN_SDK_VERSION/g" \
            -e "s/\\\$(OPENSSL_VERSION)/$OPENSSL_VERSION/g" \
            -i '' "$FWDIR/Info.plist"
        echo -e " done:\n   $FWDIR"
        echo "Created $FWDIR"
        check_bitcode $FWDIR
        make_mac_symlinks $FWDIR $SYS
    else
        echo "Skipped framework for $SYS"
    fi
}


#—————————————————————————————————————————————————————————————————————————————————————————
# build an XCFramework in the frameworks directory, with the assumption that the
# individual, desired architecture frameworks are already present.
#—————————————————————————————————————————————————————————————————————————————————————————
build_xcframework() {
    local FRAMEWORKS=($BUILD_DIR/$FWROOT/*/$FWNAME.framework)
    local ARGS=
    for ARG in ${FRAMEWORKS[@]}; do
        ARGS+="-framework ${ARG} "
    done

    echo
    xcodebuild -create-xcframework $ARGS -output "$BUILD_DIR/$FWROOT/$FWNAME.xcframework"

    # These intermediate frameworks are silly, and not needed any more.
    find ${FWROOT} -mindepth 1 -maxdepth 1 -type d -not -name "$FWNAME.xcframework" -exec rm -rf '{}' \;
}


