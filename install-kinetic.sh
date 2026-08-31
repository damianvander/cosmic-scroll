#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# install-kinetic.sh
#
# Downloads and installs the kinetic-scrolling-patched COSMIC binaries from
# this repo's GitHub releases. By default installs both patched components:
#
#     cosmic-comp      the compositor (kinetic scroll engine + per-app factors)
#     cosmic-settings  the settings app (UI toggle for smooth scrolling)
#
# It picks the release matching your installed epoch, or lets you choose one.
#
# Usage:
#   ./install-kinetic.sh                        # both components, auto-detect epoch
#   ./install-kinetic.sh cosmic-comp           # just the compositor
#   ./install-kinetic.sh cosmic-settings       # just the settings app
#   ./install-kinetic.sh epoch-1.2.0           # both, pinned to an epoch
#   ./install-kinetic.sh --latest              # both, newest patched release
#                                              # (skips epoch auto-detection)
#   ./install-kinetic.sh cosmic-comp --latest  # newest patched compositor
#
#   curl -fsSL https://raw.githubusercontent.com/damianvander/cosmic-scroll/master/install-kinetic.sh | bash
#   curl -fsSL .../install-kinetic.sh | bash -s -- cosmic-settings
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="damianvander/cosmic-scroll"          # patch repo hosting the releases
API="https://api.github.com/repos/${REPO}/releases"
INSTALL_DIR="${INSTALL_DIR:-/usr/bin}"   # override with INSTALL_DIR=... for testing

# ── Colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD='\033[1m'  GREEN='\033[32m'  YELLOW='\033[33m'
    RED='\033[31m'  CYAN='\033[36m'   RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

info()  { echo -e "${BOLD}${CYAN}::${RESET} $*"; }
ok()    { echo -e "${BOLD}${GREEN}✓${RESET} $*"; }
warn()  { echo -e "${BOLD}${YELLOW}⚠${RESET} $*"; }
die()   { echo -e "${BOLD}${RED}✗${RESET} $*" >&2; exit 1; }

# ── Parse arguments (components + optional version selector, any order) ───────
COMPONENT_SEL="all"
SELECTOR=""
for arg in "$@"; do
    case "$arg" in
        all|both)                  COMPONENT_SEL="all" ;;
        cosmic-comp|comp)          COMPONENT_SEL="cosmic-comp" ;;
        cosmic-settings|settings)  COMPONENT_SEL="cosmic-settings" ;;
        # Skip epoch auto-detection and install the newest patched release.
        --latest|-l)               SELECTOR="--latest" ;;
        -*)                        die "Unknown flag: ${arg}" ;;
        *)                         SELECTOR="$arg" ;;
    esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq gzip sha256sum; do
    command -v "$cmd" > /dev/null 2>&1 || die "Required tool '${cmd}' not found. Install it and retry."
done

# ── Detect which upstream epoch the installed binary belongs to ───────────────
# NB: callers capture stdout, so all logging in here must go to stderr —
# stdout carries only the resolved epoch tag.
detect_installed_epoch() {
    command -v "$BINARY" > /dev/null 2>&1 || { warn "$BINARY not found in PATH" >&2; return 1; }

    local version_output git_hash
    version_output=$("$BINARY" --version 2>/dev/null) || return 1
    git_hash=$(echo "$version_output" | grep -oP 'git commit \K[0-9a-f]+' || true)
    [ -z "$git_hash" ] && { warn "Could not parse git hash from: $version_output" >&2; return 1; }

    info "Installed: ${version_output}" >&2

    local tags_json tag commit
    tags_json=$(curl -fsSL "https://api.github.com/repos/${UPSTREAM}/tags?per_page=100") || return 1
    while IFS=$'\t' read -r tag commit; do
        if [[ "$commit" == "${git_hash}"* ]] || [[ "${git_hash}" == "${commit}"* ]]; then
            echo "$tag"; return 0
        fi
    done < <(echo "$tags_json" | jq -r '.[] | select(.name | startswith("epoch-")) | [.name, .commit.sha] | @tsv')
    return 1
}

# Both helpers print empty output on failure (404, network error) instead of
# a non-zero exit — a failing $(…) assignment would abort the script under
# `set -e` before any of the fallback/error paths below could run.
get_release_by_tag() { curl -fsSL "${API}/tags/$1" 2>/dev/null || true; }

# Release with the highest epoch whose tag starts with patched-<component>-.
# The API lists releases by creation date, which forced rebuilds of older
# epochs can reorder — sort by the epoch version in the tag instead.
latest_component_release() {
    curl -fsSL "${API}" 2>/dev/null | jq -c --arg p "patched-${COMPONENT}-" '
        map(select(.tag_name | startswith($p)))
        | sort_by(.tag_name | ltrimstr($p) | ltrimstr("epoch-")
                  | split(".") | map(tonumber? // 0))
        | last // empty' || true
}

# ── Resolve, download, verify, and install one component ──────────────────────
install_component() {
    COMPONENT="$1"
    case "$COMPONENT" in
        cosmic-comp)     UPSTREAM="pop-os/cosmic-comp";     BINARY="cosmic-comp" ;;
        cosmic-settings) UPSTREAM="pop-os/cosmic-settings"; BINARY="cosmic-settings" ;;
    esac

    info "Component: ${BOLD}${COMPONENT}${RESET}"

    # ── Resolve which release to install ──────────────────────────────────────
    RELEASE_TAG=""

    if [ "$SELECTOR" = "--latest" ] || [ "$SELECTOR" = "-l" ]; then
        info "Fetching latest patched release for ${COMPONENT}..."
        RELEASE_JSON=$(latest_component_release)
        [ -z "$RELEASE_JSON" ] && die "No patched-${COMPONENT}-* releases found at ${REPO}"
        RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

    elif [ -n "$SELECTOR" ]; then
        TAG="$SELECTOR"
        [[ "$TAG" != epoch-* ]] && TAG="epoch-${TAG}"
        RELEASE_TAG="patched-${COMPONENT}-${TAG}"
        info "Looking for release: ${RELEASE_TAG}"
        RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
        [ -z "$RELEASE_JSON" ] && \
            die "Release '${RELEASE_TAG}' not found.\n  See https://github.com/${REPO}/releases"

    else
        info "Detecting installed ${COMPONENT} version..."
        if EPOCH=$(detect_installed_epoch); then
            info "Detected epoch: ${BOLD}${EPOCH}${RESET}"
            RELEASE_TAG="patched-${COMPONENT}-${EPOCH}"
            RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
            if [ -z "$RELEASE_JSON" ]; then
                warn "No patched release for ${EPOCH} — falling back to latest"
                RELEASE_JSON=$(latest_component_release)
                RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
            fi
        else
            warn "Could not auto-detect epoch — using latest patched release"
            RELEASE_JSON=$(latest_component_release)
            RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
        fi
        [ -z "$RELEASE_TAG" ] && die "No patched releases found for ${COMPONENT} at ${REPO}"
    fi

    RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // .tag_name')
    info "Release:   ${BOLD}${RELEASE_NAME}${RESET}"
    info "Tag:       ${RELEASE_TAG}"

    # ── Find download URLs (assets are named after the binary) ────────────────
    BINARY_URL=$(echo "$RELEASE_JSON" | jq -r --arg n "${BINARY}.gz" \
        '.assets[] | select(.name == $n) | .browser_download_url')
    CHECKSUM_URL=$(echo "$RELEASE_JSON" | jq -r \
        '.assets[] | select(.name == "checksums-sha256.txt") | .browser_download_url')

    if [ -z "$BINARY_URL" ]; then
        BINARY_URL=$(echo "$RELEASE_JSON" | jq -r --arg n "${BINARY}" \
            '.assets[] | select(.name == $n) | .browser_download_url')
        COMPRESSED=false
    else
        COMPRESSED=true
    fi
    [ -z "$BINARY_URL" ] && die "No ${BINARY} asset found in release ${RELEASE_TAG}"

    # ── Download ──────────────────────────────────────────────────────────────
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    info "Downloading ${BINARY}..."
    if [ "$COMPRESSED" = true ]; then
        curl -fSL --progress-bar -o "${TMPDIR}/${BINARY}.gz" "$BINARY_URL"
        gzip -d "${TMPDIR}/${BINARY}.gz"
    else
        curl -fSL --progress-bar -o "${TMPDIR}/${BINARY}" "$BINARY_URL"
    fi
    chmod +x "${TMPDIR}/${BINARY}"

    # ── Verify checksum ───────────────────────────────────────────────────────
    if [ -n "$CHECKSUM_URL" ]; then
        info "Verifying checksum..."
        curl -fsSL -o "${TMPDIR}/checksums-sha256.txt" "$CHECKSUM_URL"
        EXPECTED=$(grep " ${BINARY}\$" "${TMPDIR}/checksums-sha256.txt" | awk '{print $1}' || true)
        if [ -n "$EXPECTED" ]; then
            ACTUAL=$(sha256sum "${TMPDIR}/${BINARY}" | awk '{print $1}')
            if [ "$EXPECTED" = "$ACTUAL" ]; then
                ok "Checksum verified"
            else
                die "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Got:      ${ACTUAL}"
            fi
        else
            warn "No matching checksum entry — skipping verification"
        fi
    else
        warn "No checksum file in release — skipping verification"
    fi

    NEW_VERSION=$("${TMPDIR}/${BINARY}" --version 2>/dev/null || echo "unknown")
    info "New binary: ${NEW_VERSION}"

    # ── Back up existing binary & install ─────────────────────────────────────
    INSTALL_PATH="${INSTALL_DIR}/${BINARY}"

    # Only escalate when the target isn't writable by the current user.
    SUDO="sudo"
    if [ -w "$INSTALL_DIR" ] || { [ ! -e "$INSTALL_DIR" ] && [ -w "$(dirname "$INSTALL_DIR")" ]; }; then
        SUDO=""
    fi

    if [ -f "$INSTALL_PATH" ]; then
        info "Current:   $("$INSTALL_PATH" --version 2>/dev/null || echo "unknown")"
        info "Backing up to ${INSTALL_PATH}.bak"
        $SUDO cp "$INSTALL_PATH" "${INSTALL_PATH}.bak"
        ok "Backup saved"
    fi

    info "Installing to ${INSTALL_PATH}${SUDO:+ (requires sudo)}..."
    $SUDO install -Dm0755 "${TMPDIR}/${BINARY}" "$INSTALL_PATH"
    ok "Installed successfully!"

    echo ""
    echo -e "${BOLD}${GREEN}Done!${RESET} Patched ${BINARY} is now at ${INSTALL_PATH}"
    echo ""
    if [ "$COMPONENT" = "cosmic-comp" ]; then
        echo -e "  ${CYAN}To activate:${RESET} log out and back in, or run:"
        echo -e "    ${BOLD}sudo systemctl restart cosmic-comp.service${RESET}"
    else
        echo -e "  ${CYAN}To activate:${RESET} relaunch Settings (close and reopen it)."
    fi
    echo -e "  ${CYAN}To revert:${RESET}  ${BOLD}sudo mv ${INSTALL_PATH}.bak ${INSTALL_PATH}${RESET}"
}

# ── Install the selected component(s) ─────────────────────────────────────────
# Each component runs in a subshell so one failure (die) doesn't stop the
# other; failures are collected and reported at the end.
if [ "$COMPONENT_SEL" = "all" ]; then
    COMPONENTS="cosmic-comp cosmic-settings"
else
    COMPONENTS="$COMPONENT_SEL"
fi

FAILED=""
for c in $COMPONENTS; do
    ( install_component "$c" ) || FAILED="${FAILED} ${c}"
    echo ""
done

[ -n "$FAILED" ] && die "Failed to install:${FAILED}"
exit 0
