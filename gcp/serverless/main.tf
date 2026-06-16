data "archive_file" "function" {
  type        = "zip"
  output_path = "${path.module}/function.zip"

  source {
    content  = file("${path.module}/function.py")
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "function" {
  name   = "serverless/${var.function_name}-${data.archive_file.function.output_md5}.zip"
  bucket = var.source_bucket
  source = data.archive_file.function.output_path
}

resource "google_cloudfunctions2_function" "this" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "add"
    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = "main.py"
    }

    source {
      storage_source {
        bucket = var.source_bucket
        object = google_storage_bucket_object.function.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "128Mi"
    timeout_seconds    = 30
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  location = google_cloudfunctions2_function.this.location
  name     = google_cloudfunctions2_function.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
