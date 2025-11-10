#!/usr/bin/env bash

BUCKET="$1"

if [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

URL="https://${BUCKET}.s3.amazonaws.com/?list-type=2"

HTTP_CODE=$(curl -s -o /tmp/s3check.$$ -w "%{http_code}" "$URL")

echo "HTTP code: $HTTP_CODE"
echo

case "$HTTP_CODE" in
  200)
    echo "✅ Bucket is publicly LISTABLE (anyone can list objects)."
    echo "Sample response:"
    head -n 20 /tmp/s3check.$$
    ;;
  403)
    echo "⚠️ Bucket exists but listing is not allowed for anonymous users."
    echo "It might still have some individual objects that are public."
    ;;
  404)
    echo "❌ Bucket does not exist, wrong name or wrong region."
    ;;
  *)
    echo "ℹ️ Unexpected response, inspect body:"
    head -n 20 /tmp/s3check.$$
    ;;
esac

rm -f /tmp/s3check.$$
