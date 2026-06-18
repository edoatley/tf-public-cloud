# Object Storage — Sample Output

## AWS (S3)

```
$ bash scripts/examples/object-storage/aws.sh

==> Looking up S3 bucket name
     tf-public-cloud-object-storage-a5ce
==> Upload
upload: tmp/v1.txt to s3://tf-public-cloud-object-storage-a5ce/demo/hello.txt
==> Update (overwrite)
upload: tmp/v2.txt to s3://tf-public-cloud-object-storage-a5ce/demo/hello.txt
==> Read back
download: s3://tf-public-cloud-object-storage-a5ce/demo/hello.txt to tmp/downloaded.txt
Downloaded content: updated content
==> Delete object
delete: s3://tf-public-cloud-object-storage-a5ce/demo/hello.txt
==> Empty bucket (all versions and delete markers)
{
    "Deleted": [
        {
            "Key": "demo/hello.txt",
            "VersionId": "XJRlFNvjkBBF6x6c8bbWiaTY9Z5AuoSF"
        },
        {
            "Key": "demo/hello.txt",
            "VersionId": "uaW2UMGAN.EwcyOPPvGJYm1Qxh_ZcBNo"
        }
    ]
}
{
    "Deleted": [
        {
            "Key": "demo/hello.txt",
            "VersionId": "y3zt2fMcg_KBRYs6UlXbCOXKvKzmAnfn",
            "DeleteMarker": true,
            "DeleteMarkerVersionId": "y3zt2fMcg_KBRYs6UlXbCOXKvKzmAnfn"
        }
    ]
}
==> Done
```

## GCP (Cloud Storage)

```
$ bash scripts/examples/object-storage/gcp.sh

==> Looking up GCS bucket name
     tf-public-cloud-object-storage-8679
==> Upload
Copying file:///tmp/v1.txt to gs://tf-public-cloud-object-storage-8679/demo/hello.txt
==> Update (overwrite)
Copying file:///tmp/v2.txt to gs://tf-public-cloud-object-storage-8679/demo/hello.txt
==> Read back
Copying gs://tf-public-cloud-object-storage-8679/demo/hello.txt to file:///tmp/downloaded.txt
Downloaded content: updated content
==> Delete object
Removing gs://tf-public-cloud-object-storage-8679/demo/hello.txt...
==> Empty bucket (all objects and versions)
==> Done
```

## Azure (Blob Storage)

```
$ bash scripts/examples/object-storage/azure.sh

==> Looking up Azure storage account name
     tfpubcloudobjectstor8b92
==> Upload
{
  "etag": "\"0x8DECD571C3FF833\"",
  "lastModified": "2026-06-18T16:31:55+00:00",
  "version_id": "2026-06-18T16:31:55.2992307Z"
}
==> Update (overwrite)
{
  "etag": "\"0x8DECD571D06A6BE\"",
  "lastModified": "2026-06-18T16:31:56+00:00",
  "version_id": "2026-06-18T16:31:56.6023118Z"
}
==> Read back
Downloaded content: updated content
==> Delete object
==> Empty container (delete all remaining blobs including versions)
==> Done
```
