# openssl-xcframeworks

![macOS support](https://img.shields.io/badge/macOS-10.11+-blue.svg)
![iOS support](https://img.shields.io/badge/iOS-11+-blue.svg)
![tvOS support](https://img.shields.io/badge/tvOS-11+-blue.svg)
![watchOS support](https://img.shields.io/badge/watchOS-4.0+-blue.svg)
![macOS Catalyst support](https://img.shields.io/badge/macOS%20Catalyst-10.15+-blue.svg)
![OpenSSL version](https://img.shields.io/badge/OpenSSL-1.1.1d-green.svg)
![OpenSSL version](https://img.shields.io/badge/OpenSSL-1.0.2t-green.svg)
[![license](https://img.shields.io/badge/license-Apache%202.0-lightgrey.svg)](LICENSE)

This is fork of the [OpenSSL-Apple project](https://github.com/keeshux/openssl-apple) by
Davide De Rosa, which is itself a fork of the popular work by
[Felix Schulze](https://github.com/x2on), that is a set of scripts for using self-compiled
builds of the OpenSSL library on the iPhone, Apple TV, Apple Watch, macOS, and Catalyst.

However, this repository branches from Davide's repository by emphasizing support for:

- builds XCFrameworks (hence the repository name) with truly universal libraries. With Xcode 11
  and newer, XCFrameworks offer a single package with frameworks for every, single Apple
  architecture. You no longer have to use run script build phases to slice and dice binary files;
  Xcode will choose the right framework for the given target.

- Supports all of the xcode $STANDARD_ARCHS by default for each Apple platform. This means that
  the frameworks work with your Xcode project right out of the box, with no fussing about with
  VALID_ARCHITECTURES, etc. It's tempting to leave old architectures (armv7, for example) behind,
  but Apple still seems to expect them.

- Supports OpenSSL-3.1.2 and newer. It might work with version 1.1.x, but testing begins with
  3.1.2. 


# What's Built

The `build-openssl.sh` script builds per-platform static libraries `libcrypto.a` and `libssl.a`;
if you've built multiple architectures for a platform (which is default), then these static
libraries will be fat binaries consisting of all architectures that were built.

Additionally, the per-architecture static libraries are also available, but these are generally
not useful to most programmers.

Dynamic libraries (.dylibs) have generally fallen out of favor on macOS, and are not built. You
should use frameworks instead.

The `create-framework.sh` script builds frameworks, which are the preferred and simplest forms
of library integration. Standard per-platform dynamic frameworks will be built, but
per-platform static frameworks can also be built. This latter option isn't a framework per se,
but a convenient means of distribution.

The script also builds both dynamic and static XCFrameworks, which are new in Xcode 11 and newer,
and easily allow you to integrate _all_ platforms and architectures in a single distributable.


# Compile library


Compile OpenSSL at the default version (currently 1.1.1d) for default targets:

```
./build-openssl.sh
```

Compile OpenSSL at the default version for specific targets:

```
./build-openssl.sh --version=1.1.1d --targets="ios-cross-armv7 macos64-x86_64"
```

For all options see:

```
./build-openssl.sh --help
```


# Generate frameworks

Statically linked as XCFramework:

```
./create-framework.sh static
```

Dynamically linked as XCFramework:

```
./create-framework.sh dynamic
```

# Original project

* <https://github.com/x2on/OpenSSL-for-iPhone>


# Davide de Rosa's project

* <https://github.com/keeshux/openssl-apple>


# Acknowledgements

This product includes software developed by the OpenSSL Project for use in the OpenSSL 
Toolkit. (<https://www.openssl.org/>)
