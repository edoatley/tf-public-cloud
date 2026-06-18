# Containerised App — Sample Output

## AWS (ECS Fargate + ALB)

```
$ bash scripts/examples/containerised-app-aws.sh

==> Looking up ALB DNS name
     http://tf-public-cloud-app-alb-1570170617.eu-west-2.elb.amazonaws.com
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP"
}
==> Done
```

## GCP (Cloud Run)

```
$ bash scripts/examples/containerised-app-gcp.sh gcp-sandbox-2026-18798

==> Looking up Cloud Run service URL
     https://tf-public-cloud-app-lkatnppnna-ew.a.run.app
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP"
}
==> Done
```

## Azure (Container Apps)

```
$ bash scripts/examples/containerised-app-azure.sh

==> Looking up Container App FQDN
     https://tf-public-cloud-app--6w5jnmm.redcliff-6e6eca9f.uksouth.azurecontainerapps.io
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP",
  "groups": [
    "liveness",
    "readiness"
  ]
}
==> Done
```
