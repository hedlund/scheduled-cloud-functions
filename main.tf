# -----------------------------------------------------------------------------
# PROVIDERS
# -----------------------------------------------------------------------------

provider "google" {
}

# -----------------------------------------------------------------------------
# PROJECT
# -----------------------------------------------------------------------------

resource "google_project" "project" {
  name            = "Scheduled Cloud Functions"
  project_id      = var.project_id
  billing_account = var.billing_account
}

# -----------------------------------------------------------------------------
# PUB/SUB
# -----------------------------------------------------------------------------

resource "google_project_service" "pubsub" {
  project = google_project.project.project_id
  service = "pubsub.googleapis.com"
}

resource "google_pubsub_topic" "hello" {
  project = google_project.project.project_id
  name    = "hello-topic"

  depends_on = [
    google_project_service.pubsub,
  ]
}

# -----------------------------------------------------------------------------
# STORAGE BUCKET
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "functions" {
  project = google_project.project.project_id
  name    = "${google_project.project.project_id}-functions"
}

# -----------------------------------------------------------------------------
# PUB/SUB CLOUD FUNCTION
# -----------------------------------------------------------------------------

data "archive_file" "pubsub_trigger" {
  type        = "zip"
  source_file = "${path.module}/hello_pubsub.go"
  output_path = "${path.module}/pubsub_trigger.zip"
}

resource "google_storage_bucket_object" "pubsub_trigger" {
  bucket = google_storage_bucket.functions.name
  name   = "pubsub_trigger-${data.archive_file.pubsub_trigger.output_md5}.zip"
  source = data.archive_file.pubsub_trigger.output_path
}

resource "google_project_service" "cloudbuild" {
  project = google_project.project.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "cloudfunctions" {
  project = google_project.project.project_id
  service = "cloudfunctions.googleapis.com"
}

resource "google_cloudfunctions_function" "pubsub_trigger" {
  project = google_project.project.project_id
  name    = "hello-pubsub"
  region  = "us-central1"

  entry_point = "HelloPubSub"
  runtime     = "go113"

  source_archive_bucket = google_storage_bucket.functions.name
  source_archive_object = google_storage_bucket_object.pubsub_trigger.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.hello.name
  }

  depends_on = [
    google_project_service.cloudbuild,
    google_project_service.cloudfunctions,
  ]
}

# -----------------------------------------------------------------------------
# HTTP CLOUD FUNCTION
# -----------------------------------------------------------------------------

data "archive_file" "http_trigger" {
  type        = "zip"
  source_file = "${path.module}/hello_http.go"
  output_path = "${path.module}/http_trigger.zip"
}

resource "google_storage_bucket_object" "http_trigger" {
  bucket = google_storage_bucket.functions.name
  name   = "http_trigger-${data.archive_file.http_trigger.output_md5}.zip"
  source = data.archive_file.http_trigger.output_path
}

resource "google_cloudfunctions_function" "http_trigger" {
  project = google_project.project.project_id
  name    = "hello-http"
  region  = "us-central1"

  service_account_email = google_service_account.user.email

  entry_point  = "HelloHTTP"
  runtime      = "go113"
  trigger_http = true

  source_archive_bucket = google_storage_bucket.functions.name
  source_archive_object = google_storage_bucket_object.http_trigger.name


  depends_on = [
    google_project_service.cloudbuild,
    google_project_service.cloudfunctions,
  ]
}

resource "google_service_account" "user" {
  project      = google_project.project.project_id
  account_id   = "invocation-user"
  display_name = "Invocation Service Account"
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.http_trigger.project
  region         = google_cloudfunctions_function.http_trigger.region
  cloud_function = google_cloudfunctions_function.http_trigger.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.user.email}"
}

# -----------------------------------------------------------------------------
# APP ENGINE
# -----------------------------------------------------------------------------

resource "google_app_engine_application" "app" {
  project     = google_project.project.project_id
  location_id = "us-central"
}

# -----------------------------------------------------------------------------
# SCHEDULER
# -----------------------------------------------------------------------------

resource "google_project_service" "cloudscheduler" {
  project = google_project.project.project_id
  service = "cloudscheduler.googleapis.com"
}

resource "google_cloud_scheduler_job" "hello_pubsub_job" {
  project  = google_project.project.project_id
  region   = google_cloudfunctions_function.pubsub_trigger.region
  name     = "hello-pubsub-job"
  schedule = "every 10 minutes"

  pubsub_target {
    topic_name = google_pubsub_topic.hello.id
    data       = base64encode("Pub/Sub")
  }

  depends_on = [
    google_app_engine_application.app,
    google_project_service.cloudscheduler,
  ]
}

resource "google_cloud_scheduler_job" "hello_http_job" {
  project  = google_project.project.project_id
  region   = google_cloudfunctions_function.http_trigger.region
  name     = "hello-http-job"
  schedule = "every 10 minutes"

  http_target {
    uri         = google_cloudfunctions_function.http_trigger.https_trigger_url
    http_method = "POST"
    body        = base64encode("{\"name\":\"HTTP\"}")
    oidc_token {
      service_account_email = google_service_account.user.email
    }
  }
}
