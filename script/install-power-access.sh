#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" != 0 ]]; then
  echo "This setup must be approved by an administrator." >&2
  exit 1
fi

METH_USER="${1:-}"
if [[ ! "$METH_USER" =~ ^[A-Za-z0-9._-]+$ ]] || ! /usr/bin/id "$METH_USER" >/dev/null 2>&1; then
  echo "Invalid user account." >&2
  exit 1
fi

SUDOERS_FILE="/private/etc/sudoers.d/meth"
OLD_FILE="/private/etc/sudoers.d/com.toli.meth"
TEMP_FILE="$(/usr/bin/mktemp /private/etc/sudoers.d/.meth.XXXXXX)"
trap '/bin/rm -f "$TEMP_FILE"' EXIT
/bin/chmod 0440 "$TEMP_FILE"
{
  /bin/echo "$METH_USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0"
  /bin/echo "$METH_USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1"
} > "$TEMP_FILE"
/usr/sbin/visudo -c -f "$TEMP_FILE" >/dev/null
/bin/mv -f "$TEMP_FILE" "$SUDOERS_FILE"
/usr/sbin/chown root:wheel "$SUDOERS_FILE"
/bin/chmod 0440 "$SUDOERS_FILE"
/bin/rm -f "$OLD_FILE"
/usr/sbin/visudo -c >/dev/null
if ! /usr/bin/sudo -u "$METH_USER" /usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  echo "The Meth sudo rule was installed but is not active." >&2
  exit 1
fi
