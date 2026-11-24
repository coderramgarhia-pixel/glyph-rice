#!/bin/sh
# spot: files and folders for the query $1 — up to 4 lines "d<TAB>path" / "f<TAB>path", shallow paths first.
# The query is only ever an argument here (plocate --), never part of a command.
# shortcut: plocate's index is refreshed daily (plocate-updatedb.timer); files made today show up tomorrow
[ ${#1} -ge 3 ] || exit 0 # under 3 letters plocate can't use its trigram index: a full scan, ~9 s
plocate -i -b -- "$1" 2>/dev/null | awk -v h="$HOME/" '
    # home only; no hidden dirs, node_modules, or the SDK/IDE trees (~/Android, ~/apps) that drown everything else
    index($0, h) == 1 && !/\/\./ && !/\/node_modules\// && index($0, h "Android/") != 1 && index($0, h "apps/") != 1 {
        print gsub("/", "/") "\t" $0 # depth, for the sort
        if (++n == 2000) exit
    }' | sort -n -s | head -n 4 | cut -f2- | while IFS= read -r p; do
    if [ -d "$p" ]; then printf 'd\t%s\n' "$p"; else printf 'f\t%s\n' "$p"; fi
done
