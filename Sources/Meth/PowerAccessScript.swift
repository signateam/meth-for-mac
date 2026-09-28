import Foundation

/// The privileged setup runs from this compiled-in text, never from a file in the
/// user-writable app bundle, so nothing can be swapped between approval and execution.
enum PowerAccessScript {
    static let sudoersDirectory = "/private/etc/sudoers.d"
    static let legacySudoersPaths = ["/private/etc/sudoers.d/meth", "/private/etc/sudoers.d/com.toli.meth"]

    /// macOS short names use letters, digits, '.', '_' and '-'.
    static func isValidUserName(_ user: String) -> Bool {
        !user.isEmpty && !user.hasPrefix("-") && user.unicodeScalars.allSatisfy { allowed.contains($0) || $0 == "." }
    }

    /// sudo skips files in sudoers.d whose names contain a dot, so only [A-Za-z0-9_-] is kept.
    static func sanitizedFileComponent(_ user: String) -> String {
        String(String.UnicodeScalarView(user.unicodeScalars.filter { allowed.contains($0) }))
    }

    static func sudoersPath(for user: String) -> String? {
        let component = sanitizedFileComponent(user)
        return component.isEmpty ? nil : "\(sudoersDirectory)/trymeth-\(component)"
    }

    static func ruleLines(for user: String) -> String {
        ["0", "1"].map { "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep \($0)\n" }.joined()
    }

    static func sudoersText(for user: String) -> String {
        "# Installed by Meth (trymeth.com) for closed-lid mode. Remove it from Meth Settings.\n" + ruleLines(for: user)
    }

    /// Exactly what Meth before 1.0 wrote to /etc/sudoers.d/meth.
    static func legacySudoersText(for user: String) -> String { ruleLines(for: user) }

    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Arguments: install|uninstall, user, sudoers path, sudoers text, legacy text.
    static let text = #"""
    set -euo pipefail
    mode="$1"; user="$2"; target="$3"; rule="$4"; legacy="$5"
    fail() { echo "$1" >&2; exit 1; }

    [ "$(/usr/bin/id -u)" = 0 ] || fail "This setup must be approved by an administrator."
    /usr/bin/id -u "$user" >/dev/null 2>&1 || fail "Invalid user account."
    case "$target" in
      /private/etc/sudoers.d/trymeth-*) ;;
      *) fail "Invalid sudoers path." ;;
    esac
    case "${target#/private/etc/sudoers.d/trymeth-}" in
      ""|*[!A-Za-z0-9_-]*) fail "Invalid sudoers path." ;;
    esac

    # A rule file is this user's only if every rule line names this user.
    owned_by_user() {
      [ -f "$1" ] && [ ! -L "$1" ] && /usr/bin/awk -v u="$user" 'NF && $1 !~ /^#/ && $1 != u { bad = 1 } END { exit bad }' "$1"
    }
    remove_legacy() {
      for old in /private/etc/sudoers.d/meth /private/etc/sudoers.d/com.toli.meth; do
        if [ -f "$old" ] && [ ! -L "$old" ] && printf '%s' "$legacy" | /usr/bin/cmp -s - "$old"; then
          /bin/rm -f "$old"
        fi
      done
    }

    if [ "$mode" = uninstall ]; then
      if [ -e "$target" ]; then
        owned_by_user "$target" || fail "$target does not belong to $user and was left in place."
        /bin/rm -f "$target"
      fi
      remove_legacy
      exit 0
    fi
    [ "$mode" = install ] || fail "Unknown setup mode."
    if [ -e "$target" ] && ! owned_by_user "$target"; then
      fail "$target already belongs to another account."
    fi

    temp="$(/usr/bin/mktemp /private/etc/sudoers.d/.trymeth.XXXXXX)"
    trap '/bin/rm -f "$temp"' EXIT
    printf '%s' "$rule" > "$temp"
    /usr/sbin/chown root:wheel "$temp"
    /bin/chmod 0440 "$temp"
    /usr/sbin/visudo -cf "$temp" >/dev/null || fail "The Meth sudo rule did not validate."
    /bin/mv -f "$temp" "$target"
    if ! /usr/sbin/visudo -c >/dev/null; then
      /bin/rm -f "$target"
      fail "The sudo configuration did not validate, so the Meth rule was removed."
    fi
    if ! /usr/bin/sudo -u "$user" /usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
      fail "The Meth sudo rule was installed but is not active."
    fi
    remove_legacy
    """#
}
