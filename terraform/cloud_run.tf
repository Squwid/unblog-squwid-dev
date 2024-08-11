resource "google_cloud_run_service" "blog_service" {
  name     = "squwid-blog"
  location = "us-central1"

  metadata {
    annotations = {
      "run.googleapis.com/ingress" : "all"
    }
  }

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "0"
        "autoscaling.knative.dev/maxScale" = "3"
      }
    }

    spec {
      service_account_name  = google_service_account.backend.email
      container_concurrency = 5
      timeout_seconds       = 30

      containers {
        image = local.backend_image

        resources {
          limits = {
            memory = "256Mi"
            cpu    = "1000m"
          }
        }

        ports {
          container_port = "8000"
        }

        env {
          name  = "BGCS_BUCKET"
          value = google_storage_bucket.blog_bucket.name
        }
        env {
          name  = "BGCS_NOT_FOUND_FILE"
          value = "index.html"
        }

        env {
          name  = "BGCS_DEFAULT_FILE"
          value = "index.html"
        }
      }
    }
  }

  # Split Traffic - https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#example-usage---cloud-run-service-traffic-split
  traffic {
    percent         = 100
    latest_revision = true
  }
  autogenerate_revision_name = true

  depends_on = [
    google_service_account.backend
  ]
}
data "google_iam_policy" "blog_noauth" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}

resource "google_cloud_run_service_iam_policy" "blog_noauth" {
  location = google_cloud_run_service.blog_service.location
  project  = google_cloud_run_service.blog_service.project
  service  = google_cloud_run_service.blog_service.name

  policy_data = data.google_iam_policy.blog_noauth.policy_data
}

resource "google_cloud_run_domain_mapping" "blog" {
  location = "us-central1"
  name     = local.backend_url

  metadata {
    namespace = local.project
  }

  spec {
    route_name = google_cloud_run_service.blog_service.name
  }
}