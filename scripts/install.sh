#!/bin/bash
set -e

REPO="eqtylab/reala2a"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="real-a2a"

case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64)   arch="x64" ;;
    arm64|aarch64)  arch="arm64" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

platform="${os}-${arch}"
archive_name="${BINARY_NAME}-${platform}.tar.gz"

echo "Fetching latest version..."
latest_tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)

if [ -z "$latest_tag" ]; then
    echo "Failed to fetch latest version" >&2
    exit 1
fi

echo "Installing ${BINARY_NAME} ${latest_tag} for ${platform}..."

archive_url="https://github.com/${REPO}/releases/download/${latest_tag}/${archive_name}"
checksum_url="${archive_url}.sha256"

mkdir -p "$INSTALL_DIR"

tmp_dir=$(mktemp -d)
tmp_file="${tmp_dir}/${archive_name}"

curl -fsSL -o "$tmp_file" "$archive_url"

expected_checksum=$(curl -fsSL "$checksum_url" | cut -d' ' -f1)

if [ "$(uname -s)" = "Darwin" ]; then
    actual_checksum=$(shasum -a 256 "$tmp_file" | cut -d' ' -f1)
else
    actual_checksum=$(sha256sum "$tmp_file" | cut -d' ' -f1)
fi

if [ "$actual_checksum" != "$expected_checksum" ]; then
    echo "Checksum verification failed!" >&2
    rm -rf "$tmp_dir"
    exit 1
fi

tar -xzf "$tmp_file" -C "$tmp_dir"
mv "${tmp_dir}/${BINARY_NAME}" "$INSTALL_DIR/${BINARY_NAME}"
chmod +x "$INSTALL_DIR/${BINARY_NAME}"
rm -rf "$tmp_dir"

echo ""
echo "${BINARY_NAME} ${latest_tag} installed to ${INSTALL_DIR}/${BINARY_NAME}"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "${INSTALL_DIR} is not in your PATH. Add it with:"
    echo ""

    case "$SHELL" in
        */zsh)  shell_config="~/.zshrc" ;;
        */bash) shell_config="~/.bashrc" ;;
        *)      shell_config="your shell config" ;;
    esac

    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${shell_config}"
    echo "  source ${shell_config}"
fi

echo ""
echo "=========================================="
echo "  INSTALL THE CLAUDE CODE PLUGIN"
echo "=========================================="
echo ""
echo "  /plugin marketplace add eqtylab/reala2a"
echo "  /plugin install ralph2ralph@reala2a"
echo ""
echo "Then restart Claude Code."
echo ""
