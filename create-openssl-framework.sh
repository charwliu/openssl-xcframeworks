#!/bin/sh

set -u
set -x
XFWNAME=COpenSSL.xcframework

if [ ! -d lib ]; then
  echo "Please run build-openssl.sh first!"
  exit 1
fi

if [ -d $XFWNAME ]; then
  echo "* Removing existing $XFWNAME copy"
  rm -rf $XFWNAME
fi

LIBS=""
LIBTOOL_FLAGS="-no_warning_for_no_symbols -static"

# Copy include files into temporary dir
make_include_dir()
{
  mkdir xfwinclude
  if [ $? -ne 0 ]; then
   exit 1
  fi
  cp -r include/openssl xfwinclude/
  if [ $? -ne 0 ]; then
   exit 1
  fi
  cp assets/{openssl.h,module.modulemap} xfwinclude
  if [ $? -ne 0 ]; then
   exit 1
  fi
}

# Combine libssl and libcrypto into single per-platform library
make_platform_lib()
{
  SLICE_LIBS=`ls lib/lib*-$SLICE.a 2>/dev/null`
  mkdir -p lib/$SLICE
  SLICE_OUT="lib/$SLICE/OpenSSL.a"
  if [ ${#SLICE_LIBS} -gt 0 ]; then
    echo "* Creating library for $SLICE"
    libtool $LIBTOOL_FLAGS -o $SLICE_OUT $SLICE_LIBS
    if [ $? -ne 0 ]; then
      exit 1
    fi
    LIBS="$LIBS -library $SLICE_OUT -headers xfwinclude"
  else
    echo "* Skipping $SLICE. No libraries found."
  fi
}

# Remove temporary files
remove_temp_files()
{
  rm lib/OpenSSL-*.a 2>/dev/null
  rm -r xfwinclude 2>/dev/null
}

remove_temp_files
make_include_dir
PLATFORMS=("iPhoneOS" "iPhoneSimulator" "appleTVOS" "appleTVSimulator" "macOS" "Catalyst" "watchOS" "WatchSimulator")
for PLATFORM in ${PLATFORMS[@]}; do
  SLICE="$PLATFORM"
  make_platform_lib
done

echo "* Creating $XFWNAME"
xcodebuild -create-xcframework $LIBS -output $XFWNAME
remove_temp_files
echo "Done!"
