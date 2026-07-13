#!/usr/bin/env bash
set -euo pipefail

#
# Update Creality Print AppImage launcher
#
# Edit this value each time Creality releases a new AppImage.
#

NEW_APPIMAGE_FILENAME="CrealityPrint-V7.2.0.5226-x86_64-Release.AppImage"

SOURCE_DIR="$HOME/Downloads"
INSTALL_DIR="$HOME/Applications/CrealityPrint"
STABLE_LINK="$INSTALL_DIR/CrealityPrint.AppImage"
DESKTOP_FILE="$HOME/.local/share/applications/crealityprint.desktop"

SOURCE_FILE="$SOURCE_DIR/$NEW_APPIMAGE_FILENAME"
TARGET_FILE="$INSTALL_DIR/$NEW_APPIMAGE_FILENAME"

echo "Creality Print AppImage updater"
echo "--------------------------------"
echo "Source file:  $SOURCE_FILE"
echo "Install dir:  $INSTALL_DIR"
echo "Stable link:  $STABLE_LINK"
echo

if [[ ! -f "$SOURCE_FILE" && ! -f "$TARGET_FILE" ]]; then
    echo "ERROR: Could not find the AppImage in either location:"
    echo "  $SOURCE_FILE"
    echo "  $TARGET_FILE"
    echo
    echo "Download the new AppImage to $SOURCE_DIR or update NEW_APPIMAGE_FILENAME in this script."
    exit 1
fi

mkdir -p "$INSTALL_DIR"

if [[ -f "$SOURCE_FILE" ]]; then
    echo "Moving AppImage into install directory..."
    mv "$SOURCE_FILE" "$TARGET_FILE"
else
    echo "AppImage already exists in install directory."
fi

echo "Setting executable permission..."
chmod +x "$TARGET_FILE"

echo "Updating stable symlink..."
ln -sfn "$TARGET_FILE" "$STABLE_LINK"

if [[ -f "$DESKTOP_FILE" ]]; then
    echo "Updating desktop launcher..."
    sed -i "s|^Exec=.*|Exec=$STABLE_LINK|" "$DESKTOP_FILE"
else
    echo "Desktop file not found, creating a basic launcher..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Creality Print
Comment=Creality Print
Exec=$STABLE_LINK
Terminal=false
Categories=Graphics;3DGraphics;Utility;
EOF
fi

echo "Refreshing desktop application database..."
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo
echo "Done."
echo
echo "Current symlink:"
ls -la "$STABLE_LINK"
echo
echo "Resolved target:"
readlink -f "$STABLE_LINK"
echo
echo "Desktop launcher Exec line:"
grep '^Exec=' "$DESKTOP_FILE"
