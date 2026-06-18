# Serverless — Sample Output

## AWS (Lambda)

```
$ bash scripts/examples/serverless-aws.sh

==> Looking up Lambda Function URL
     https://jwudaxtsgqkyzcp6n2lqsm4orq0cmesv.lambda-url.eu-west-2.on.aws/
==> GET ?a=3&b=5 (expect 8)
     Got expected result: 8.0
==> GET ?a=-1&b=1 (expect 0)
     Got expected result: 0.0
==> GET ?a=bad (expect 400)
     Got expected 400
==> Done
```

## GCP (Cloud Functions v2)

```
$ bash scripts/examples/serverless-gcp.sh gcp-sandbox-2026-18798

==> Looking up Cloud Function URL
     https://tf-public-cloud-add-lkatnppnna-ew.a.run.app
==> GET ?a=3&b=5 (expect 8)
     Got expected result: 8.0
==> GET ?a=-1&b=1 (expect 0)
     Got expected result: 0.0
==> GET ?a=bad (expect 400)
     Got expected 400
==> Done
```

## Azure (Azure Functions)

```
$ bash scripts/examples/serverless-azure.sh

==> Looking up Function App hostname
     https://tfpubcloudfn-2679.azurewebsites.net/api/add
==> GET ?a=3&b=5 (expect 8)
     Got expected result: 8.0
==> GET ?a=-1&b=1 (expect 0)
     Got expected result: 0.0
==> GET ?a=bad (expect 400)
     Got expected 400
==> Done
```
