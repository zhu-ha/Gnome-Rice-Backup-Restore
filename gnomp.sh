#!/usr/bin/env bash
BACKUP_DIR="$HOME/fedora-gnome-backup"
DATE=$(date +%Y%m%d)
ARCHIVE="$HOME/gnome-setup-$DATE.tar.gz"

# --- FUNCTION: Dependency Check ---
check_deps() {
    echo "Checking essential dependencies..."
    DEPS=(dconf gsettings tar gnome-extensions curl wget unzip sudo fc-cache)
    MISSING=0
    for pkg in "${DEPS[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            echo "ERROR: Missing dependency: $pkg"
            MISSING=1
        fi
    done
    if [ "$MISSING" -eq 1 ]; then
        echo "FAILURE: Critical dependencies are missing. Install them and run the script again:"
        echo "   sudo dnf install gnome-extensions-app curl wget unzip"
        exit 1
    else
        echo "All required dependencies are present."
    fi
}

# --- FUNCTION: Backup ---
backup() {
    echo "Initiating GNOME 47 environment backup..."
    mkdir -p "$BACKUP_DIR"

    echo "Dumping GNOME and extension settings..."
    dconf dump /org/gnome/ > "$BACKUP_DIR/dconf-gnome.conf"
    dconf dump /org/gnome/shell/extensions/ > "$BACKUP_DIR/dconf-extensions.conf"

    echo "Saving list of installed extensions..."
    gnome-extensions list > "$BACKUP_DIR/extensions-list.txt"

    echo "Backing up user customizations (themes, icons, fonts)..."
    cp -r ~/.themes "$BACKUP_DIR/" 2>/dev/null
    cp -r ~/.icons "$BACKUP_DIR/" 2>/dev/null
    cp -r ~/.local/share/fonts "$BACKUP_DIR/fonts" 2>/dev/null

    echo "Backing up current wallpaper..."
    WALLPAPER=$(gsettings get org.gnome.desktop.background picture-uri | sed "s|'file://||;s|'||g")
    if [ -f "$WALLPAPER" ]; then
        cp "$WALLPAPER" "$BACKUP_DIR/wallpaper.png"
    fi

    echo "Backing up system-wide resources (themes, icons, fonts, extensions) - SUDO REQUIRED."
    sudo cp -r /usr/share/themes "$BACKUP_DIR/usr_themes" 2>/dev/null
    sudo cp -r /usr/share/icons "$BACKUP_DIR/usr_icons" 2>/dev/null
    sudo cp -r /usr/share/fonts "$BACKUP_DIR/usr_fonts" 2>/dev/null
    sudo cp -r /usr/share/gnome-shell/extensions "$BACKUP_DIR/usr_extensions" 2>/dev/null

    echo "Backing up GDM (login screen) theme..."
    sudo cp -r /usr/share/gnome-shell/theme "$BACKUP_DIR/gdm-theme" 2>/dev/null

    echo "Creating compressed backup archive..."
    tar -czf "$ARCHIVE" -C "$BACKUP_DIR" .
    echo "Backup procedure finished."
    echo "Archive location: $ARCHIVE"
}

# --- FUNCTION: Restore ---
restore() {
    read -p "Enter path to your backup archive (.tar.gz): " ARCHIVE
    if [ ! -f "$ARCHIVE" ]; then
        echo "ERROR: Archive file not found!"; exit 1
    fi

    echo "Initiating GNOME 47 environment restore..."
    mkdir -p "$BACKUP_DIR"
    tar -xzf "$ARCHIVE" -C "$BACKUP_DIR"

    echo "Restoring GNOME settings..."
    dconf load /org/gnome/ < "$BACKUP_DIR/dconf-gnome.conf" 2>/dev/null
    dconf load /org/gnome/shell/extensions/ < "$BACKUP_DIR/dconf-extensions.conf" 2>/dev/null

    echo "Restoring user customizations (themes, icons, fonts)..."
    cp -r "$BACKUP_DIR/.themes" ~ 2>/dev/null
    cp -r "$BACKUP_DIR/.icons" ~ 2>/dev/null
    mkdir -p ~/.local/share/fonts
    cp -r "$BACKUP_DIR/fonts"/* ~/.local/share/fonts/ 2>/dev/null

    echo "Restoring wallpaper settings..."
    if [ -f "$BACKUP_DIR/wallpaper.png" ]; then
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$BACKUP_DIR/wallpaper.png"
        gsettings set org.gnome.desktop.background picture-uri "file://$BACKUP_DIR/wallpaper.png"
    fi

    echo "Restoring system-wide resources - SUDO REQUIRED."
    sudo cp -r "$BACKUP_DIR/usr_themes"/* /usr/share/themes/ 2>/dev/null
    sudo cp -r "$BACKUP_DIR/usr_icons"/* /usr/share/icons/ 2>/dev/null
    sudo cp -r "$BACKUP_DIR/usr_fonts"/* /usr/share/fonts/ 2>/dev/null
    sudo cp -r "$BACKUP_DIR/usr_extensions"/* /usr/share/gnome-shell/extensions/ 2>/dev/null

    echo "Restoring GDM (login screen) theme..."
    sudo cp -r "$BACKUP_DIR/gdm-theme"/* /usr/share/gnome-shell/theme/ 2>/dev/null

    echo "Attempting automatic reinstallation of online extensions..."
    while read -r ext_uuid; do
        [ -z "$ext_uuid" ] && continue
        if ! gnome-extensions info "$ext_uuid" &>/dev/null; then
            echo "Installing missing extension: $ext_uuid"
            VERSION=$(gnome-shell --version | awk '{print $3}' | cut -d'.' -f1,2)
            INFO_URL="https://extensions.gnome.org/extension-info/?uuid=$ext_uuid&shell_version=$VERSION"
            ZIP_PATH=$(curl -s "$INFO_URL" | grep -oP '(?<=\"download_url\": \")[^\"]*')
            if [ -n "$ZIP_PATH" ]; then
                wget -qO /tmp/ext.zip "https://extensions.gnome.org$ZIP_PATH"
                unzip -oq /tmp/ext.zip -d ~/.local/share/gnome-shell/extensions/"$ext_uuid"
                echo "Extension $ext_uuid installed successfully."
            else
                echo "WARNING: Failed to find download URL for $ext_uuid"
            fi
        fi
        gnome-extensions enable "$ext_uuid" 2>/dev/null
    done < "$BACKUP_DIR/extensions-list.txt"

    echo "Refreshing font cache and desktop environment..."
    fc-cache -rv > /dev/null
    sudo update-desktop-database > /dev/null 2>&1
    echo "Restore procedure finished. Log out or run 'Alt+F2' then 'r' to reload GNOME Shell."
}

# --- FUNCTION: Verify Backup ---
verify() {
    echo "Initiating backup integrity verification..."
    read -p "Enter path to your backup archive (.tar.gz): " ARCHIVE
    if [ ! -f "$ARCHIVE" ]; then
        echo "ERROR: Archive file not found!"; exit 1
    fi

    REQUIRED=(dconf-gnome.conf extensions-list.txt wallpaper.png)
    tar -tzf "$ARCHIVE" > /tmp/backup_contents.txt

    for file in "${REQUIRED[@]}"; do
        if grep -q "$file" /tmp/backup_contents.txt; then
            echo "File present: $file"
        else
            echo "WARNING: Critical file missing: $file"
        fi
    done
    echo "Verification complete."
}

# --- MAIN ENTRY ---
case "$1" in
    backup)
        check_deps
        backup ;;
    restore)
        check_deps
        restore ;;
    verify)
        verify ;;
    *)
        echo "Usage: $0 [backup|restore|verify]"
        exit 1 ;;
esac

