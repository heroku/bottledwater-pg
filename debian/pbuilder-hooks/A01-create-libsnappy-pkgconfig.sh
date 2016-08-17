#!/bin/sh -e

# libsnappy packages don't include their own pkg-config, so we have to create
# it

# Ask the Debian package what version of snappy we have
libsnappy_debversion=`dpkg-query --show --showformat='${Version}' libsnappy-dev`
libsnappy_version=`echo "$libsnappy_debversion" | sed -rn 's/^([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/p'`
[ -n "$libsnappy_version" ] || {
  echo "Unexpected libsnappy version format: $libsnappy_debversion" >&2
  exit 1
}

pkgconfig_dir=/usr/local/lib/pkgconfig
mkdir -p $pkgconfig_dir

cat <<PC >$pkgconfig_dir/libsnappy.pc
Name: libsnappy
Description: Snappy is a compression library
Version: ${libsnappy_version}
URL: https://google.github.io/snappy/
Libs: -lsnappy
PC
