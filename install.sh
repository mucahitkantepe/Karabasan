#!/bin/bash
set -euo pipefail

echo "Installing Karabasan..."

curl -sL https://github.com/mucahitkantepe/Karabasan/releases/latest/download/Karabasan.zip -o /tmp/Karabasan.zip
unzip -oq /tmp/Karabasan.zip -d /Applications
rm /tmp/Karabasan.zip
xattr -cr /Applications/Karabasan.app

# Allow current user to toggle pmset sleep without a password
echo "Setting up passwordless sleep toggle for $(whoami) (requires sudo)..."
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" | sudo tee /etc/sudoers.d/karabasan > /dev/null
sudo chmod 0440 /etc/sudoers.d/karabasan

echo "Done. Opening Karabasan..."
open /Applications/Karabasan.app
