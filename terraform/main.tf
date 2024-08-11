provider "google" {
  project = "squid-cloud"
  region  = "us-central1"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.38.0"
    }
  }

  backend "gcs" {
    bucket = "bytegolf-tf-state"
    prefix = "blog/state"
  }
}

locals {
  project       = "squid-cloud"
  backend_image = "squwid/bgcs-site-proxy:v0.3"
  backend_url   = "blog.squwid.dev"
}


resource "google_storage_bucket" "blog_bucket" {
  name          = "squwid-blog"
  location      = "US-CENTRAL1"
  force_destroy = false

  uniform_bucket_level_access = true
}

resource "google_service_account" "backend" {
  account_id   = "bg-blog-backend"
  display_name = "BG Blog Backend Service Account"
}

resource "google_storage_bucket_iam_member" "bucket_object_viewer" {
  bucket = google_storage_bucket.blog_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backend.email}"
}