#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Packages that target the home directory (~)
USER_PACKAGES=(
    "emacs"
    "kde"
)

# Packages that target the root directory (/)
SYSTEM_PACKAGES=(
    "keyd"
)

echo "==> Stowing user packages into ~..."
for pkg in "${USER_PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$pkg" ]; then
        echo "Stowing $pkg..."
        stow -v -R -t "$HOME" -d "$DOTFILES_DIR" "$pkg"
    else
        echo "Warning: Package directory $pkg not found, skipping."
    fi
done

echo "==> Stowing system packages into /..."
for pkg in "${SYSTEM_PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$pkg" ]; then
        echo "Stowing $pkg..."
        sudo stow -v -R -t / -d "$DOTFILES_DIR" "$pkg"
    else
        echo "Warning: Package directory $pkg not found, skipping."
    fi
done

# Reload keyd if the systemd service is active
if command -v systemctl &>/dev/null && systemctl is-active --quiet keyd; then
    echo "==> Reloading keyd configuration..."
    sudo keyd reload
fi

echo "==> Dotfiles installation complete!"
