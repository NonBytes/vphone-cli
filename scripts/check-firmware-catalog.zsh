#!/bin/zsh
set -euo pipefail

# Flags iPhone/iPad builds Apple has signed (per api.ipsw.me) that are newer
# than this fork's hand-curated VPhoneFirmwareCatalog.swift, for every device
# already listed there. Read-only: it never edits the catalog, it only tells
# you which device needs a new pairing added by hand (see
# Skills/authoring-patch-sets/SKILL.md if the new build also needs a preset
# change). A device not yet in the catalog is not discovered; this only
# watches devices already tracked.
#
# Works by scanning every "..._Restore.ipsw" URL in the catalog file and
# keeping the last (newest, since each list is oldest-first) version seen per
# device identifier embedded in the URL itself — so it doesn't care whether
# the URL came from the dedicated iPhone17,3 `pairings` list or the generic
# `iPhoneReleases` / `iPadReleases` tables.

catalog=${0:a:h}/../VPhoneKit/VPhoneCoreKit/Firmware/VPhoneFirmwareCatalog.swift
if [[ ! -f $catalog ]]; then
  print -u2 "Catalog not found at $catalog"
  exit 2
fi
if ! command -v jq >/dev/null; then
  print -u2 'jq is required (brew install jq).'
  exit 2
fi

typeset -A latest
while IFS= read -r url; do
  version=$(print -r -- "$url" | grep -oE '_[0-9]+(\.[0-9]+)*_[0-9A-Za-z]+_Restore\.ipsw$' \
    | sed -E 's/^_//; s/_[0-9A-Za-z]+_Restore\.ipsw$//')
  [[ -z $version ]] && continue
  for device in ${(f)"$(print -r -- "$url" | grep -oE '(iPhone|iPad)[0-9]+,[0-9]+')"}; do
    latest[$device]=$version
  done
done < <(grep -oE 'https://[^"]+_Restore\.ipsw' "$catalog")

behind=0
checked=0
for device in ${(ko)latest}; do
  (( checked += 1 ))
  catalog_version=$latest[$device]
  signed=$(curl -fsSL "https://api.ipsw.me/v4/device/${device}?type=ipsw" \
    | jq -r '[.firmwares[] | select(.signed == true)][0].version // "unknown"')
  if [[ $signed == "unknown" ]]; then
    print -u2 "  $device: could not reach ipsw.me, skipped"
  elif [[ $signed != "$catalog_version" ]]; then
    (( behind += 1 ))
    print "  $device: catalog has $catalog_version, Apple signs $signed"
  fi
done

print "Checked $checked device(s) already in the catalog; $behind behind."
if (( behind > 0 )); then
  print 'Add the missing pairing(s) to VPhoneFirmwareCatalog.swift by hand, then update'
  print 'the hardcoded counts in VPhoneCoreKitTests/Firmware/FirmwarePickerTests.swift and'
  print 'FirmwareCatalogReportTests.swift to match.'
fi
exit 0
