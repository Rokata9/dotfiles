#!/bin/bash
# setup-mac.sh - install everything ~/.emacs.d/init.el needs on a Mac.
#
# Usage (from Terminal):
#   bash ~/.emacs.d/setup-mac.sh
#
# Safe to run again: every step checks first and skips what is already there.
# It asks for your password (Homebrew, Xcode tools) and may ask y/n questions.
#
# What it installs:
#   1. Xcode Command Line Tools  clang, make, git, clangd, lldb-dap (debugger)
#   2. Homebrew                  the package manager for everything below
#   3. Emacs+ (Emacs 31)         /Applications/Emacs.app
#   4. Tools                     ripgrep (Cmd+Shift+F search);
#                                LLVM only if Apple's clangd / lldb-dap are missing
#   5. Fonts                     editor fonts: Hack (the one init.el uses,
#                                see my/font), DejaVu Sans Mono, Ubuntu Mono,
#                                JetBrains Mono;
#                                Symbols Nerd Font Mono (icons, the exact
#                                version the icon package expects)
#
# Not here, because Emacs does it on its first start (takes 1-2 minutes):
#   Emacs packages (from GNU ELPA / MELPA) and tree-sitter grammars.

set -euo pipefail

# The icon font, from the icon package (nerd-icons) itself, so its version
# always matches. Same file and folder as M-x nerd-icons-install-fonts.
NERD_FONT_URL="https://raw.githubusercontent.com/rainstormstudio/nerd-icons.el/main/fonts/NFM.ttf"
NERD_FONT_FILE="$HOME/Library/Fonts/NFM.ttf"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m  %s\n' "$*"; }
note() { printf '    \033[33mnote\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ask() {   # ask "Question?"  -> 0 for yes, 1 for no (default: no)
  local answer=""
  read -r -p "    $1 [y/N] " answer || true
  [[ "$answer" == [yY]* ]]
}

# --- 0. Checks ---------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."
ARCH="$(uname -m)"                       # arm64 (Apple Silicon) or x86_64 (Intel)
MACOS="$(sw_vers -productVersion)"
step "macOS $MACOS on $ARCH"

# --- 1. Xcode Command Line Tools ----------------------------------------------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "installed ($(xcode-select -p))"
else
  note "A window opens: click Install and wait for it to finish."
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  ok "installed"
fi

# --- 2. Homebrew --------------------------------------------------------------
step "Homebrew"
if [[ "$ARCH" == "arm64" ]]; then BREW_PREFIX=/opt/homebrew; else BREW_PREFIX=/usr/local; fi
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
ok "$(brew --version | head -n 1)"

# Emacs reads PATH from your login shell (zsh), so brew's tools must be on
# PATH there too, or Emacs won't find rg, etc.
ZPROFILE="$HOME/.zprofile"
if ! grep -qs "brew shellenv" "$ZPROFILE"; then
  # shellcheck disable=SC2016  # $(...) must stay literal in the file
  printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >> "$ZPROFILE"
  ok "added Homebrew to PATH in $ZPROFILE"
else
  ok "Homebrew is on PATH in $ZPROFILE"
fi

brew_has()      { brew list --formula "$1" >/dev/null 2>&1; }
brew_has_cask() { brew list --cask "$1" >/dev/null 2>&1; }
font_exists()   {   # font_exists "JetBrainsMono*"  (in your or the system's Fonts)
  compgen -G "$HOME/Library/Fonts/$1" >/dev/null || compgen -G "/Library/Fonts/$1" >/dev/null
}

# --- 3. Emacs+ ----------------------------------------------------------------
step "Emacs+ (GNU Emacs 31)"
# Any Emacs+ variant counts (cask emacs-plus-app@next, formula emacs-plus@31, ...).
formulas="$(brew list --formula 2>/dev/null || true)"
casks="$(brew list --cask 2>/dev/null || true)"
if grep -q '^emacs-plus' <<<"$formulas"$'\n'"$casks"; then
  ok "installed"
elif [[ -d /Applications/Emacs.app ]]; then
  note "/Applications/Emacs.app exists but is not Emacs+; leaving it alone."
  note "This config is made for Emacs+ 31. To switch: move that app to the"
  note "Trash, then run this script again."
else
  # Homebrew 6+ only loads third-party taps you trust (older versions
  # have no `brew trust`, so skip it there).
  if brew help trust >/dev/null 2>&1; then
    brew trust d12frosted/emacs-plus
  fi
  brew tap d12frosted/emacs-plus
  if [[ "$ARCH" == "arm64" ]]; then
    brew install --cask emacs-plus-app   # pre-built, about 1 minute
  else
    note "Intel Mac: Emacs+ builds from source (about 30 minutes)."
    brew install emacs-plus
    ln -sf "$(brew --prefix emacs-plus)/Emacs.app" /Applications/Emacs.app
  fi
  ok "installed: /Applications/Emacs.app"
fi

# --- 4. Tools -----------------------------------------------------------------
step "Tools"
command -v rg >/dev/null || brew install ripgrep
ok "ripgrep ($(command -v rg))"

# clangd (code intelligence) and lldb-dap (debugger) come with Apple's tools.
# init.el falls back to Homebrew's LLVM when they are missing.
missing=""
for tool in clangd lldb-dap; do
  if path="$(xcrun --find "$tool" 2>/dev/null)" && [[ -x "$path" ]]; then
    ok "$tool ($path)"
  else
    missing="$missing $tool"
  fi
done
if [[ -n "$missing" ]]; then
  note "Not in Apple's tools:$missing. Installing Homebrew's LLVM instead."
  brew_has llvm || brew install llvm
  ok "llvm ($(brew --prefix llvm)/bin)"
fi

# --- 5. Fonts -----------------------------------------------------------------
step "Fonts"
# Editor fonts. init.el uses Hack (`my/font'); the others are there to try.
font_cask() {   # font_cask CASK FILE-PATTERN NAME
  font_exists "$2" || brew install --cask "$1"
  ok "$3"
}
font_cask font-hack           "Hack-*"           "Hack"
font_cask font-dejavu         "DejaVuSansMono*"  "DejaVu Sans Mono"
font_cask font-ubuntu-mono    "UbuntuMono-*"     "Ubuntu Mono"
font_cask font-jetbrains-mono "JetBrainsMono*"   "JetBrains Mono"

# Another copy of the icon font with the same name can hide this one, and
# then new icons show as boxes with hex codes (e.g. collapsed folders).
if brew_has_cask font-symbols-only-nerd-font; then
  note "Homebrew's font-symbols-only-nerd-font is installed too. It has the"
  note "same name as the icon font and can be an older version."
  if ask "Remove it (recommended)?"; then
    brew uninstall --cask font-symbols-only-nerd-font
    ok "removed"
  fi
fi

mkdir -p "$(dirname "$NERD_FONT_FILE")"
tmp="$(mktemp)"
if curl -fsSL "$NERD_FONT_URL" -o "$tmp" && [[ -s "$tmp" ]]; then
  if [[ -f "$NERD_FONT_FILE" ]] && cmp -s "$tmp" "$NERD_FONT_FILE"; then
    ok "Symbols Nerd Font Mono (up to date)"
  else
    mv "$tmp" "$NERD_FONT_FILE"
    chmod 644 "$NERD_FONT_FILE"
    ok "Symbols Nerd Font Mono -> $NERD_FONT_FILE"
  fi
else
  note "Could not download the icon font. Emacs tries again on its first start."
fi
rm -f "$tmp"

# --- Done ---------------------------------------------------------------------
step "Done"
[[ -f "$HOME/.emacs.d/init.el" ]] ||
  note "No ~/.emacs.d/init.el yet: copy your .emacs.d folder to your home folder."
cat <<EOF
    Next: open Emacs (Spotlight: "Emacs"). The first start downloads the
    Emacs packages and tree-sitter grammars, which takes 1-2 minutes.
    If Emacs was open while fonts were installed, quit and reopen it.
EOF
