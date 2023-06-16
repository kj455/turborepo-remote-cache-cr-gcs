terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.69.1"
    }
  }
}

provider "google" {
  credentials = file("../credentials.json")
  project     = var.project_id
  region      = var.region
}

resource "google_storage_bucket" "static-site" {
  name          = var.bucket_name
  location      = var.bucket_location
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "service_account" {
  account_id = "turborepo-remote-cache-runner"
}

resource "google_storage_hmac_key" "key" {
  service_account_email = google_service_account.service_account.email
}

resource "google_project_service" "artifacts" {
  service = "artifactregistry.googleapis.com"
}

resource "google_artifact_registry_repository" "my-repo" {
  location      = var.region
  repository_id = "turborepo-remote-cache-repo"
  format        = "DOCKER"
}

resource "google_cloud_run_service" "default" {
  name     = "cloudrun-turborepo-remote-cache"
  location = var.region

  template {
    spec {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.my-repo.repository_id}/turborepo-remote-cache:1.13.2"

        env {
          name  = "NODE_ENV"
          value = "production"
        }
        env {
          name  = "TURBO_TOKEN"
          value = var.turbo_token
        }
        env {
          name  = "AWS_ACCESS_KEY_ID"
          value = google_storage_hmac_key.key.access_id
        }
        env {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = google_storage_hmac_key.key.secret
        }
        env {
          name  = "S3_ENDPOINT"
          value = "https://storage.googleapis.com"
        }
        env {
          name  = "AWS_REGION"
          value = "auto"
        }
        env {
          name  = "STORAGE_PROVIDER"
          value = "s3"
        }
        env {
          name  = "STORAGE_PATH"
          value = var.bucket_name
        }
      }
    }
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  service  = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}