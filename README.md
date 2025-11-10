# s3_check_and_crawl
s3 buckets check and crawl in bash


Usage:
  ./check_and_crawl_s3.sh bucket1 bucket2 ...
  ./check_and_crawl_s3.sh -f buckets.txt

What it does:
  1) For each bucket, checks anonymous LIST permission via curl (?list-type=2).
  2) If HTTP 200, extracts object keys from XML and shows a sample.
  3) For a few sample keys, does an anonymous HEAD to see if objects are publicly readable.

NOTE: Use only on buckets you own or are allowed to test.
