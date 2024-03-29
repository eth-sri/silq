#!/bin/bash

VERSION=$(cat version-ldc.txt)
NAME="ldc2-$VERSION-windows-x64"

LDMD="wine ./$NAME/bin/ldmd2.exe";

# release build
$LDMD -O -inline -J. -Jlibrary *.d ast/*.d util/*.d -ofsilq
