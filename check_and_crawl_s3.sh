#!/usr/bin/env bash
#
# check_and_crawl_s3.sh
#
# Usage:
#   ./check_and_crawl_s3.sh bucket1 bucket2 ...
#   ./check_and_crawl_s3.sh -f buckets.txt   # one bucket per line
#
# Requirements:
#   - bash
#   - curl
#

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<EOF
Usage:
  $0 bucket1 bucket2 ...
  $0 -f buckets.txt

What it does:
  1) For each bucket, checks anonymous LIST permission via curl (?list-type=2).
  2) If HTTP 200, extracts object keys from XML and shows a sample.
  3) For a few sample keys, does an anonymous HEAD to see if objects are publicly readable.

NOTE: Use only on buckets you own or are allowed to test.
EOF
  exit 0
fi

# Collect bucket names
BUCKETS=()
if [ "${1:-}" = "-f" ]; then
  if [ -z "${2:-}" ]; then
    echo "Provide a file with bucket names after -f" >&2
    exit 1
  fi
  if [ ! -f "$2" ]; then
    echo "File not found: $2" >&2
    exit 1
  fi
  while IFS= read -r line; do
    line_trimmed="$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line_trimmed" ] && continue
    BUCKETS+=("$line_trimmed")
  done <"$2"
else
  if [ "$#" -eq 0 ]; then
    echo "No buckets provided. Use -h for help." >&2
    exit 1
  fi
  for b in "$@"; do
    BUCKETS+=("$b")
  done
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Checking ${#BUCKETS[@]} bucket(s)..."

for bucket in "${BUCKETS[@]}"; do
  echo
  echo "==== Bucket: $bucket ===="

  URL="https://${bucket}.s3.amazonaws.com/?list-type=2"

  # Anonymous list
  XML_OUT="${TMPDIR}/${bucket}.xml"
  HTTP_CODE=$(curl -s -o "$XML_OUT" -w '%{http_code}' "$URL" || true)

  echo "HTTP code for anonymous LIST: $HTTP_CODE"

  if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Bucket is publicly LISTABLE (anonymous can list objects)."

    # Extract keys from XML: <Key>...</Key>
    KEYS_FILE="${TMPDIR}/${bucket}.keys"
    sed -n 's/.*<Key>\(.*\)<\/Key>.*/\1/p' "$XML_OUT" > "$KEYS_FILE"

    TOTAL_KEYS=$(wc -l < "$KEYS_FILE" | tr -d ' ')
    echo "Approx number of keys in this first listing page: $TOTAL_KEYS"

    echo
    echo "Sample keys (up to 20):"
    head -n 20 "$KEYS_FILE" | sed 's/^/ - /'

    echo
    echo "Testing anonymous access (HEAD) on first few keys:"
    head -n 5 "$KEYS_FILE" | while IFS= read -r key; do
      [ -z "$key" ] && continue
      # URL encode spaces minimally (good enough for many cases)
      SAFE_KEY=$(printf '%s' "$key" | sed 's/ /%20/g')
      OBJ_URL="https://${bucket}.s3.amazonaws.com/${SAFE_KEY}"

      # -I for HEAD request
      CODE=$(curl -s -o /dev/null -w '%{http_code}' -I "$OBJ_URL" || echo "ERR")
      if [ "$CODE" = "200" ]; then
        echo " - $key  -> 200 OK (publicly readable)"
      elif [ "$CODE" = "403" ]; then
        echo " - $key  -> 403 AccessDenied (not readable anonymously)"
      elif [ "$CODE" = "404" ]; then
        echo " - $key  -> 404 NotFound"
      elif [ "$CODE" = "ERR" ]; then
        echo " - $key  -> error reaching object URL"
      else
        echo " - $key  -> HTTP $CODE"
      fi
    done

    echo
    echo "Raw XML of listing (first 40 lines) if you want to see it:"
    sed -n '1,40p' "$XML_OUT"

  elif [ "$HTTP_CODE" = "403" ]; then
    echo "⚠️ Bucket exists but anonymous LIST is denied (AccessDenied)."
    echo "It may still have some public objects if object ACLs/policies allow,"
    echo "but you need known keys or do an authenticated audit from inside the account."
    echo "XML error snippet:"
    sed -n '1,20p' "$XML_OUT"
  elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ Bucket not found at this endpoint (404). Wrong name, or different region/layout."
    echo "Response body:"
    sed -n '1,20p' "$XML_OUT"
  else
    echo "ℹ️ Unexpected HTTP code: $HTTP_CODE"
    echo "Response body (first 40 lines):"
    sed -n '1,40p' "$XML_OUT"
  fi
done

echo
echo "Done."
