#!/bin/sh
# Bootstrap das minhas maquinas (macOS / Arch Linux).
#
#   curl -fsSL wladmirjunior.github.io/i | sh
#
# Instala o chezmoi e o 1Password, espera o SSH agent do 1Password e aplica o
# repo privado de dotfiles via SSH. Precisa de git: no Mac, se as Command Line
# Tools nao estiverem instaladas, o macOS oferece instalar no primeiro uso.
set -eu

REPO="git@github.com:WladmirJunior/dotfiles.git"
BIN="$HOME/.local/bin"
# Chave ed25519 publicada pelo GitHub (docs.github.com, "GitHub's SSH key
# fingerprints"). Fixa aqui pra nao confiar no primeiro contato.
GITHUB_HOSTKEY="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

# Com `curl | sh` o stdin e o proprio script: o que for interativo le do tty.
[ -r /dev/tty ] || die "rode num terminal interativo"

os="$(uname -s)"
case "$os" in
    Darwin) agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ;;
    Linux)  agent_sock="$HOME/.1password/agent.sock" ;;
    *)      die "sistema nao suportado: $os (Windows: irm wladmirjunior.github.io/w | iex)" ;;
esac

# --- chezmoi -----------------------------------------------------------------

if command -v chezmoi >/dev/null 2>&1; then
    chezmoi="$(command -v chezmoi)"
else
    chezmoi="$BIN/chezmoi"
    if [ ! -x "$chezmoi" ]; then
        say "instalando chezmoi em $BIN"
        mkdir -p "$BIN"
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN"
    fi
fi

# --- 1Password ---------------------------------------------------------------

install_1password_mac() {
    [ -d /Applications/1Password.app ] && return 0
    say "instalando 1Password (vai pedir a senha do Mac)"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/1Password.pkg" https://downloads.1password.com/mac/1Password.pkg
    sudo installer -pkg "$tmp/1Password.pkg" -target / </dev/tty
    rm -rf "$tmp"
}

install_1password_arch() {
    command -v 1password >/dev/null 2>&1 && return 0
    say "instalando 1Password do AUR (vai pedir a senha do sudo)"
    sudo pacman -S --needed --noconfirm git base-devel </dev/tty
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --import
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/1password.git "$tmp/1password"
    (cd "$tmp/1password" && makepkg -si --noconfirm </dev/tty)
    rm -rf "$tmp"
}

case "$os" in
    Darwin) install_1password_mac ;;
    Linux)
        [ -f /etc/arch-release ] || die "so Arch e suportado no Linux por enquanto"
        install_1password_arch
        ;;
esac

# --- SSH agent ---------------------------------------------------------------

if [ ! -S "$agent_sock" ]; then
    say "abra o 1Password, entre na conta e ative:"
    say "  Settings > Developer > Use the SSH agent"
    case "$os" in
        Darwin) open -a 1Password ;;
        Linux)  (1password >/dev/null 2>&1 &) ;;
    esac
    while [ ! -S "$agent_sock" ]; do
        printf 'Enter quando o agent estiver ativo... '
        read -r _ </dev/tty
    done
fi
export SSH_AUTH_SOCK="$agent_sock"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
grep -qF "$GITHUB_HOSTKEY" "$HOME/.ssh/known_hosts" 2>/dev/null \
    || echo "$GITHUB_HOSTKEY" >> "$HOME/.ssh/known_hosts"

# --- dotfiles ----------------------------------------------------------------

say "aplicando dotfiles"
exec "$chezmoi" init --apply "$REPO" </dev/tty
