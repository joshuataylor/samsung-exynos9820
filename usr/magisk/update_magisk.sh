#!/bin/bash

set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ver="$(cat "$DIR/magisk_version" 2>/dev/null || echo -n 'none')"

if [[ "x$1" =~ x.*delta ]]
then
	if [ "$1" = "delta" ]; then
		nver="$(curl -s https://github.com/HuskyDG/magisk-files/releases | grep -m 1 -Poe '[a-f0-9]{8}-delta')"
	else
		nver="$1"
	fi
	magisk_link="https://github.com/HuskyDG/magisk-files/releases/download/${nver}/app-release.apk"
elif [ "x$1" = "xcanary" ]
then
	nver="canary"
	magisk_link="https://github.com/topjohnwu/magisk-files/raw/${nver}/app-debug.apk"
elif [ "x$1" = "xalpha" ]
then
	nver="alpha"
	magisk_link="https://github.com/vvb2060/magisk_files/raw/${nver}/app-release.apk"
else
	dash='-'
	if [ "x$1" = "x" ]; then
		nver="$(curl -s https://github.com/topjohnwu/Magisk/releases | grep -m 1 -Poe 'Magisk v[\d\.]+' | cut -d ' ' -f 2)"
	else
		nver="$1"
	fi
	if [ "$nver" = "v26.3" ]; then
		dash='.'
	fi
	magisk_link="https://github.com/topjohnwu/Magisk/releases/download/${nver}/Magisk${dash}${nver}.apk"
fi

if [ \( -n "$nver" \) -a \( "$nver" != "$ver" \) -o ! \( -f "$DIR/magiskinit" \) -o \( "$nver" = "canary" \) -o \( "$nver" = "alpha" \) ]
then
	echo "Updating Magisk from $ver to $nver"
	curl -s --output "$DIR/magisk.zip" -L "$magisk_link"
  if grep -F 'Not Found' "$DIR/magisk.zip"; then
		curl -s --output "$DIR/magisk.zip" -L "${magisk_link%.apk}.zip"
	fi
  # Magisk v28+ ships a single magiskinit and a single magisk binary per ABI
  # (topjohnwu/Magisk#8629), so detect the layout from the APK contents rather
  # than the version string. canary, alpha and delta builds can be either.
  if unzip -l "$DIR/magisk.zip" lib/arm64-v8a/libmagisk.so >/dev/null 2>&1; then
    echo "Single magisk binary layout (Magisk v28+)"
    rm -f "$DIR/magisk" "$DIR/magisk.xz" "$DIR/init-ld" "$DIR/init-ld.xz" "$DIR/stub" "$DIR/stub.xz"
    unzip -o "$DIR/magisk.zip" lib/arm64-v8a/libmagiskinit.so lib/arm64-v8a/libmagisk.so -d "$DIR"
    mv -f "$DIR/lib/arm64-v8a/libmagiskinit.so" "$DIR/magiskinit"
    mv -f "$DIR/lib/arm64-v8a/libmagisk.so" "$DIR/magisk"
    xz --force --check=crc32 "$DIR/magisk"
    {
      echo "dir /.backup 0705 0 0"
      echo "file /init usr/magisk/magiskinit 0750 0 0"
      echo "file /.backup/.magisk usr/magisk/backup_magisk 0000 0 0"
      echo "dir /overlay.d 0750 0 0"
      echo "dir /overlay.d/sbin 0750 0 0"
      echo "file /overlay.d/sbin/magisk.xz usr/magisk/magisk.xz 0644 0 0"
    } > "$DIR/initramfs_list"
    # init-ld appeared in v28, the stub APK was dropped in v31
    if unzip -o "$DIR/magisk.zip" lib/arm64-v8a/libinit-ld.so -d "$DIR" >/dev/null 2>&1; then
      mv -f "$DIR/lib/arm64-v8a/libinit-ld.so" "$DIR/init-ld"
      xz --force --check=crc32 "$DIR/init-ld"
      echo "file /overlay.d/sbin/init-ld.xz usr/magisk/init-ld.xz 0644 0 0" >> "$DIR/initramfs_list"
    fi
    if unzip -o "$DIR/magisk.zip" assets/stub.apk -d "$DIR" >/dev/null 2>&1; then
      mv -f "$DIR/assets/stub.apk" "$DIR/stub"
      xz --force --check=crc32 "$DIR/stub"
      echo "file /overlay.d/sbin/stub.xz usr/magisk/stub.xz 0644 0 0" >> "$DIR/initramfs_list"
    fi
    rm -rf "$DIR/lib" "$DIR/assets"
  else
    echo "Both arch magiskinit, extracting both 32 and 64 bit (Magisk <28)"
    if unzip -o "$DIR/magisk.zip" arm/magiskinit64 -d "$DIR"; then
      mv -f "$DIR/arm/magiskinit64" "$DIR/magiskinit"
      : > "$DIR/magisk32.xz"
      : > "$DIR/magisk64.xz"
    elif unzip -o "$DIR/magisk.zip" lib/armeabi-v7a/libmagiskinit.so lib/armeabi-v7a/libmagisk32.so lib/armeabi-v7a/libmagisk64.so -d "$DIR"; then
      mv -f "$DIR/lib/armeabi-v7a/libmagiskinit.so" "$DIR/magiskinit"
      mv -f "$DIR/lib/armeabi-v7a/libmagisk32.so" "$DIR/magisk32"
      mv -f "$DIR/lib/armeabi-v7a/libmagisk64.so" "$DIR/magisk64"
      xz --force --check=crc32 "$DIR/magisk32" "$DIR/magisk64"
    elif unzip -o "$DIR/magisk.zip" lib/arm64-v8a/libmagiskinit.so lib/armeabi-v7a/libmagisk32.so lib/arm64-v8a/libmagisk64.so assets/stub.apk -d "$DIR"; then
      mv -f "$DIR/lib/arm64-v8a/libmagiskinit.so" "$DIR/magiskinit"
      mv -f "$DIR/lib/armeabi-v7a/libmagisk32.so" "$DIR/magisk32"
      mv -f "$DIR/lib/arm64-v8a/libmagisk64.so" "$DIR/magisk64"
      mv -f "$DIR/assets/stub.apk" "$DIR/stub"
      xz --force --check=crc32 "$DIR/magisk32" "$DIR/magisk64" "$DIR/stub"
    else
      unzip -o "$DIR/magisk.zip" lib/arm64-v8a/libmagiskinit.so lib/armeabi-v7a/libmagisk32.so lib/arm64-v8a/libmagisk64.so -d "$DIR"
      mv -f "$DIR/lib/arm64-v8a/libmagiskinit.so" "$DIR/magiskinit"
      mv -f "$DIR/lib/armeabi-v7a/libmagisk32.so" "$DIR/magisk32"
      mv -f "$DIR/lib/arm64-v8a/libmagisk64.so" "$DIR/magisk64"
      xz --force --check=crc32 "$DIR/magisk32" "$DIR/magisk64"
    fi
    cp "$DIR/initramfs_list_split" "$DIR/initramfs_list"
  fi
  echo -n "$nver" > "$DIR/magisk_version"
  rm "$DIR/magisk.zip"
  touch "$DIR/initramfs_list"
else
	echo "Nothing to be done: Magisk version $nver"
fi
