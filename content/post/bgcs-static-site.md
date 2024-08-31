+++
title = "GCS Static Site with HTTPS"
description = "A GCS static site wrapper for Cloud Run."
date = "2024-08-24"
projects = ["BGCS", "Squwid's Blog"]
author = "Squwid"
+++

There is an inherit problem with Google Cloud Storage site hosting on GCP, which is that to enable HTTPS you must put a load balancer in front of the storage bucket. For small static websites with low amounts of traffic, adding a load balancer can get expensive quick (upwards of 20$ per month)!  This is where [bgcs-site-proxy](https://github.com/Squwid/bgcs-site-proxy) comes in handy.

## BGCS Site Proxy

Let me start with saying that for most cases of static website hosting HTTPS is absolutely not a requirement, it is still a good look for modern websites in 2024. This website (my [blog website](https://blog.squwid.dev/)) is an example for using the static-site wrapper. 

I originally leveraged a Google Cloud Load Balancer as suggested [by the documentation](https://cloud.google.com/storage/docs/hosting-static-website#lb-ssl) to achieve HTTPS for my blog, with routing rules to point to my website bucket statically served publically from Google Cloud Storage. Although I had other routes to various other websites, this load balancer was costing me upwards of 20$ per month almost *solely* for SSL.

<p align="center">
  <img src="https://img.byte.golf/hLctaQ97JfJV.png" alt="Load Balancer Configuration">
</p>

## Cloud Run

This got me thinking back to my favorite way to host websites with small amounts of traffic: [Google Cloud Run](https://cloud.google.com/run?hl=en). Cloud Run is a serverless platform that allows for running of containerized applications, which you pay for variably based on the amount of traffic your instance gets. Cloud Run also allows to map custom domains to containers and handles SSL certificates automatically for secure HTTPS connections.

The idea was to basically create a load balancer Docker container that would read files from a non-public Google Cloud Storage bucket while being configurable enough for all the static sites that I host.

Most of this comes with the path logic of correctly mapping requests to their file, for instance a request to `/about` should fetch the file `/about/index.html` from the specified bucket.

```go
var defaultFile = "index.html"

func modifyPath(path string) string {
	if len(path) == 0 || path[len(path)-1] == '/' {
		path += defaultFile
	} else if filepath.Ext(path) == "" {
		path += "/" + defaultFile
	}
	return path
}
```

### Setup

The [bgcs-site-proxy container](https://hub.docker.com/repository/docker/squwid/bgcs-site-proxy/tags) is configurable enough to satisfy all of *my* use cases based on the following environmental variables. 

- `BG_BUCKET_NAME`: Which bucket your Cloud Run instance should be reading from.
- `BGCS_NOT_FOUND_FILE`: What file should be served when the requested file is not found. If empty, the request returns a 400.
- `BGCS_DEFAULT_FILE`: Defaults to `index.html`. When changed, a `/about` request will fetch `/about/${BGCS_DEFAULT_FILE}`.

There is also an example of a simple Terraform setup in the [example folder of the Github Repo](https://github.com/Squwid/bgcs-site-proxy/example) for easy deployments.