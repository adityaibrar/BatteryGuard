#!/bin/bash
# install_helper.sh
# Script untuk install Ozone Helper sebagai LaunchDaemon
# Jalankan SEKALI dari Terminal dengan: sudo bash install_helper.sh
#
# Setelah ini, helper akan otomatis start saat Mac dinyalakan

set -e

APP_PATH="/Applications/Ozone.app"
HELPER_BINARY="$APP_PATH/Contents/MacOS/com.ibrardev.Ozone.Helper"
PLIST_SRC="$APP_PATH/Contents/Library/LaunchDaemons/com.ibrardev.Ozone.Helper.plist"
HELPER_DEST="/Library/PrivilegedHelperTools/com.ibrardev.Ozone.Helper"
PLIST_DEST="/Library/LaunchDaemons/com.ibrardev.Ozone.Helper.plist"

# Cek root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Script ini harus dijalankan dengan sudo!"
  echo "   Jalankan: sudo bash install_helper.sh"
  exit 1
fi

echo "🔧 Installing Ozone Helper..."

# Cek app ada
if [ ! -d "$APP_PATH" ]; then
  echo "❌ Ozone.app tidak ada di /Applications!"
  echo "   Pastikan Anda sudah copy Ozone.app ke /Applications"
  exit 1
fi

# Buat folder tujuan jika belum ada
mkdir -p /Library/PrivilegedHelperTools

# Copy helper binary
echo "  → Copying helper binary..."
cp "$HELPER_BINARY" "$HELPER_DEST"
chmod 755 "$HELPER_DEST"
chown root:wheel "$HELPER_DEST"

# Copy & modifikasi plist untuk menunjuk ke path permanent
echo "  → Installing LaunchDaemon plist..."
cp "$PLIST_SRC" "$PLIST_DEST"

# Update plist: ganti BundleProgram dengan path absolute dan tambah KeepAlive
/usr/libexec/PlistBuddy -c "Delete :BundleProgram" "$PLIST_DEST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :Program string $HELPER_DEST" "$PLIST_DEST"
# KeepAlive: pastikan launchd selalu menjalankan helper (tidak on-demand)
/usr/libexec/PlistBuddy -c "Delete :KeepAlive" "$PLIST_DEST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "$PLIST_DEST"

chmod 644 "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"

# Unload dulu jika sudah ada
launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
sleep 1

# Load helper
echo "  → Starting helper daemon..."
launchctl bootstrap system "$PLIST_DEST"

# Verifikasi
sleep 2
if launchctl print system/com.ibrardev.Ozone.Helper &>/dev/null; then
  echo ""
  echo "✅ Ozone Helper berhasil diinstall dan berjalan!"
  echo "   Buka Ozone.app untuk mengatur charge limit."
else
  echo ""
  echo "⚠️  Helper mungkin belum berjalan. Coba restart Mac, lalu buka Ozone.app"
fi
