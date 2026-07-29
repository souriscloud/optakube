#!/usr/bin/env python3
"""Validate appcast.xml against the version the app actually ships.

The repo *is* the Sparkle feed (SUFeedURL points at raw.githubusercontent.com on the
default branch), so anything committed here reaches every installed copy on its next
update check. These are the invariants that, if broken, silently disable auto-update:

  * the XML parses at all;
  * the newest item's shortVersionString matches CFBundleShortVersionString;
  * the newest item's sparkle:version matches CFBundleVersion;
  * every enclosure has a length, and the newest one is signed;
  * sparkle:version values are unique and increase with the release order.
"""

import plistlib
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCAST = "appcast.xml"
PLIST = "Sources/OptaKube/Info.plist"

# 0.1.0 predates the EdDSA signing key, so it can never be signed. Sparkle ignores
# unsigned items; it stays listed only for changelog continuity.
UNSIGNED_LEGACY = {"0.1.0"}

failures = []
notes = []


def fail(message):
    failures.append(message)


def sparkle_attr(element, name):
    return element.get(f"{{{SPARKLE}}}{name}")


try:
    root = ET.parse(APPCAST).getroot()
except ET.ParseError as exc:
    print(f"::error file={APPCAST}::not well-formed XML: {exc}")
    sys.exit(1)

with open(PLIST, "rb") as handle:
    plist = plistlib.load(handle)

plist_short = plist["CFBundleShortVersionString"]
plist_build = plist["CFBundleVersion"]

items = root.findall(".//item")
if not items:
    print(f"::error file={APPCAST}::no <item> elements found")
    sys.exit(1)

def sparkle_text(element, name):
    value = element.findtext(f"{{{SPARKLE}}}{name}")
    return value.strip() if value else None


parsed = []
for index, item in enumerate(items):
    # generate_appcast writes these as child elements; Sparkle also accepts them as
    # attributes on the item or the enclosure, so check all three spellings.
    short = sparkle_text(item, "shortVersionString") or sparkle_attr(item, "shortVersionString")
    build = sparkle_text(item, "version") or sparkle_attr(item, "version")
    enclosure = item.find("enclosure")

    if enclosure is not None:
        short = short or sparkle_attr(enclosure, "shortVersionString")
        build = build or sparkle_attr(enclosure, "version")

    title = (item.findtext("title") or f"item[{index}]").strip()

    if build is None or not build.isdigit():
        fail(f"{title}: missing or non-numeric sparkle:version ({build!r})")
        continue
    if not short:
        fail(f"{title}: missing sparkle:shortVersionString")
        continue

    if enclosure is None:
        fail(f"{title}: no <enclosure>")
        continue
    if not enclosure.get("length"):
        fail(f"{title}: enclosure has no length attribute")
    if not sparkle_attr(enclosure, "edSignature") and short not in UNSIGNED_LEGACY:
        fail(f"{title}: enclosure is not signed (sparkle:edSignature missing)")

    # Deltas are optional, but a delta without a signature or length is unusable.
    for delta in item.findall(f"{{{SPARKLE}}}deltas/enclosure"):
        delta_to = sparkle_attr(delta, "version") or "?"
        delta_from = sparkle_attr(delta, "deltaFrom") or "?"
        label = f"{title} delta {delta_from}->{delta_to}"
        if not delta.get("length"):
            fail(f"{label}: no length attribute")
        if not sparkle_attr(delta, "edSignature"):
            fail(f"{label}: not signed")

    parsed.append((int(build), short, title, index))

if not parsed:
    print(f"::error file={APPCAST}::no usable items")
    sys.exit(1)

builds = [build for build, _, _, _ in parsed]
duplicates = {b for b in builds if builds.count(b) > 1}
if duplicates:
    fail(
        "duplicate sparkle:version values "
        + ", ".join(str(b) for b in sorted(duplicates))
        + " — a repeated build means Sparkle never sees the newer release"
    )

# Document order is newest-first; that plus descending builds is what generate_appcast
# produces, and it's what Sparkle's own ordering assumes.
if builds != sorted(builds, reverse=True):
    notes.append(
        "items are not in descending sparkle:version order: "
        + ", ".join(str(b) for b in builds)
    )

newest_build, newest_short, newest_title, _ = max(parsed, key=lambda entry: entry[0])

print(f"appcast newest: {newest_short} (build {newest_build})  [{newest_title}]")
print(f"Info.plist:     {plist_short} (build {plist_build})")
print(f"items: {len(parsed)}")

if newest_short != plist_short:
    fail(
        f"newest appcast item is {newest_short} but the app ships "
        f"{plist_short} — released users would be offered the wrong version"
    )
if str(newest_build) != str(plist_build):
    fail(
        f"newest appcast sparkle:version is {newest_build} but CFBundleVersion "
        f"is {plist_build} — Sparkle compares these and would not offer the update"
    )

for note in notes:
    print(f"::warning file={APPCAST}::{note}")

for message in failures:
    print(f"::error file={APPCAST}::{message}")

if failures:
    sys.exit(1)

print("appcast OK")
