#!/bin/sh
# Bootstrap das minhas maquinas (macOS / Arch Linux).
#
#   curl -fsSL wladmirjunior.github.io/i | sh
#
# Instala o chezmoi e o 1Password, espera o SSH agent do 1Password e aplica o
# repo privado de dotfiles via SSH. No Mac sem Command Line Tools instala um git
# standalone (dugite-native) em ~/.local, sem Xcode CLT nem Homebrew.
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

install_clt_mac() {
    [ -x /Library/Developer/CommandLineTools/usr/bin/clang ] && return 0
    say "instalando Command Line Tools da Apple"
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    prod="$(softwareupdate -l 2>/dev/null | grep -B 1 -E "Command Line Tools" | awk -F"*" "/^ *\*/ {print $2}" | sed -e "s/^ *//" | tr -d "\n")"
    if [ -n "$prod" ]; then
        softwareupdate -i "$prod" --verbose || true
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
}

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
    Darwin)
        install_1password_mac
        install_clt_mac
        ;;
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

# Pin da chave do GitHub para evitar "Too many authentication failures" quando ha muitas chaves no 1Password
gh_key="$(SSH_AUTH_SOCK="$agent_sock" ssh-add -L 2>/dev/null | grep -F "SSH: GitHub - Personal Mac" | head -n 1 || true)"
if [ -n "$gh_key" ]; then
    printf '%s\n' "$gh_key" > "$HOME/.ssh/github.pub"
    chmod 644 "$HOME/.ssh/github.pub"
    export GIT_SSH_COMMAND="ssh -o IdentitiesOnly=yes -o IdentityFile=$HOME/.ssh/github.pub"
fi

# --- git ---------------------------------------------------------------------

# No Mac sem Command Line Tools, /usr/bin/git e um stub que abre o dialogo de
# instalacao (e `command -v git` passa). Entao git "de verdade" e: um binario que
# nao seja o stub, ou o stub com as CLT instaladas (xcode-select -p so e seguro
# de chamar depois de achar o stub, e so se o diretorio das CLT existir).
real_git() {
    g="$(command -v git 2>/dev/null)" || return 1
    [ "$os" = Darwin ] && [ "$g" = /usr/bin/git ] || return 0
    [ -x /Library/Developer/CommandLineTools/usr/bin/git ] \
        || [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/git ]
}

# git standalone do dugite-native (o mesmo do GitHub Desktop), versao e SHA-256
# fixados. Fica em ~/.local/share/git-<versao> com um wrapper em ~/.local/bin/git.
install_git_standalone() {
    gver="2.53.0"
    base="https://github.com/desktop/dugite-native/releases/download/v2.53.0-4"
    case "$(uname -m)" in
        arm64)
            asset="dugite-native-v2.53.0-4098283-macOS-arm64.tar.gz"
            sha="f9dc64635a5b62fbd7ad95db73268bbb8912255ac516d65d37bf7af22fcb8ffe" ;;
        x86_64)
            asset="dugite-native-v2.53.0-4098283-macOS-x64.tar.gz"
            sha="ae6686718aa34f4140424db16b92a47dcffd6d1f312eb8b5f3b267f7404e2680" ;;
        *) die "arquitetura sem git standalone: $(uname -m)" ;;
    esac
    dest="$HOME/.local/share/git-$gver"
    say "sem git (Command Line Tools ausentes): instalando git $gver em $dest"
    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 -o "$tmp/$asset" "$base/$asset" || die "falhou baixar o git"
    [ "$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)" = "$sha" ] || die "SHA-256 do git nao confere"
    rm -rf "$dest"
    mkdir -p "$dest" "$BIN"
    tar -xzf "$tmp/$asset" -C "$dest"
    rm -rf "$tmp"
    [ -x "$dest/bin/git" ] || die "git nao encontrado em $dest/bin"
    cat > "$BIN/git" <<WRAP
#!/bin/sh
GIT_DIR_BASE="$dest"
export GIT_EXEC_PATH="\${GIT_EXEC_PATH:-\$GIT_DIR_BASE/libexec/git-core}"
export GIT_TEMPLATE_DIR="\${GIT_TEMPLATE_DIR:-\$GIT_DIR_BASE/share/git-core/templates}"
exec "\$GIT_DIR_BASE/bin/git" "\$@"
WRAP
    chmod +x "$BIN/git"
}

# Sempre na frente do PATH: o stub /usr/bin/git nao pode ganhar do nosso.
PATH="$BIN:$PATH"; export PATH
if [ "$os" = Darwin ] && ! real_git; then
    install_git_standalone
fi
"$(command -v git)" --version >/dev/null 2>&1 || die "git nao funciona"

# --- dotfiles ----------------------------------------------------------------

say "aplicando dotfiles"
# DOTFILES_BRANCH=mac-intel sh i  (perfil do Mac Intel enquanto o branch nao esta no main)
exec "$chezmoi" init --apply ${DOTFILES_BRANCH:+--branch "$DOTFILES_BRANCH"} "$REPO" </dev/tty
