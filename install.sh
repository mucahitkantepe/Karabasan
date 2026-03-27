#!/bin/bash
set -euo pipefail

echo "Installing Karabasan..."

curl -sL https://github.com/mucahitkantepe/Karabasan/releases/latest/download/Karabasan.zip -o /tmp/Karabasan.zip
unzip -oq /tmp/Karabasan.zip -d /Applications
rm /tmp/Karabasan.zip
xattr -cr /Applications/Karabasan.app

echo "Done. Opening Karabasan..."
open /Applications/Karabasan.app
