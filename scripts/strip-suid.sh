#!/bin/sh
set -eu
# Remove all SUID and SGID bits
find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true
