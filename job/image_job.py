import io
import logging
import os
import sys
import time

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from PIL import Image, ImageStat
import psycopg
from psycopg.rows import dict_row

LOCK_ID = 1
MAX_ATTEMPTS = 3


class Broken(Exception):
    pass


def list_objects(s3, bucket):
    pages = s3.get_paginator("list_objects_v2").paginate(Bucket=bucket)
    return [(obj["Key"], obj["ETag"].strip('"'))
            for page in pages for obj in page.get("Contents", [])]


def decide(row, etag):
    if row is None or row["etag"] != etag:
        return True, 0
    if row["status"] == "failed" and row["retryable"]:
        return True, row["attempts"]
    return False, row["attempts"]


def analyse(data):
    try:
        with Image.open(io.BytesIO(data), formats=["PNG", "JPEG"]) as image:
            width, height = image.size
            grey = image.convert("I").point(lambda v: v / 257) if image.mode.startswith("I") else image
            brightness = ImageStat.Stat(grey.convert("L")).mean[0]
    except Exception as error:
        raise Broken(f"not a valid PNG or JPEG image: {error}")
    return width, height, brightness


class Store:
    def __init__(self, connection):
        self.connection = connection

    def lock(self):
        self.connection.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))

    def rows(self):
        rows = self.connection.execute("SELECT * FROM image_results").fetchall()
        return {row["image_key"]: row for row in rows}

    def save(self, key, etag, status, attempts, width=None, height=None,
             brightness=None, error=None, retryable=False):
        self.connection.execute(
            """INSERT INTO image_results
                   (image_key, etag, status, width, height, brightness, error, attempts, retryable)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (image_key) DO UPDATE SET
                   etag = EXCLUDED.etag, status = EXCLUDED.status,
                   width = EXCLUDED.width, height = EXCLUDED.height,
                   brightness = EXCLUDED.brightness, error = EXCLUDED.error,
                   attempts = EXCLUDED.attempts, retryable = EXCLUDED.retryable,
                   updated_at = now()""",
            (key, etag, status, width, height, brightness, error, attempts, retryable),
        )


def fail(store, key, etag, attempts, error, retryable):
    store.save(key, etag, "failed", attempts, error=str(error), retryable=retryable)
    print(f"{key} failed: {error}")
    return error


def process(s3, store, bucket, key, etag, attempts):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        attempts += 1
        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            data = response["Body"].read()
            etag = response["ETag"].strip('"')
            break
        except (BotoCoreError, ClientError) as e:
            logging.warning(f"{key} attempt {attempt} failed: {e}")
            if attempt == MAX_ATTEMPTS:
                return fail(store, key, etag, attempts, e, retryable=True)
            time.sleep(attempt)

    try:
        width, height, brightness = analyse(data)
    except Broken as e:
        return fail(store, key, etag, attempts, e, retryable=False)

    store.save(key, etag, "done", attempts, width, height, brightness)
    print(f"{key} done")
    return None


def run(s3, store, bucket):
    store.lock()
    objects = list_objects(s3, bucket)
    rows = store.rows()
    counts = dict(done=0, skipped=0, failed=0)
    minio_failed = False

    for key, etag in objects:
        todo, attempts = decide(rows.get(key), etag)
        if not todo:
            print(f"{key} skipped")
            counts["skipped"] += 1
            continue
        error = process(s3, store, bucket, key, etag, attempts)
        if error is None:
            counts["done"] += 1
        else:
            counts["failed"] += 1
            if not isinstance(error, Broken):
                minio_failed = True

    logging.info("summary: " + " ".join(f"{k}={v}" for k, v in counts.items()))
    return 1 if minio_failed else 0


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        s3 = boto3.client("s3", config=Config(
            connect_timeout=5, read_timeout=30, s3={"addressing_style": "path"}))

        with psycopg.connect(autocommit=True, row_factory=dict_row) as connection:
            return run(s3, Store(connection), os.environ.get("S3_BUCKET", "images"))
    except Exception as error:
        logging.error(f"run failed: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
