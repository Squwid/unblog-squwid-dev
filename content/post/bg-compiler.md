+++
title = "Bytegolf Compiler"
description = "Some quick description"
date = "2024-03-30"
projects = ["Bytegolf", "Bytegolf Compiler"]
author = "Squwid"
+++

The goal of the [Bytegolf Compiler](https://github.com/Squwid/bg-compiler) is
to take untrusted user code snippets, run them in a secure environment, and
return the output to the client. This post will cover the architecture, usage,
and future for the Bytegolf Compiler.

All the code for this post is available at the
[bg-compiler Github Repo](https://github.com/Squwid/bg-compiler).

## Why?

Bytegolf started as a code game similar to [Code Golf](https://en.wikipedia.org/wiki/Code_golf),
with the goal of adding more dimensions instead of solely code length like CPU,
Memory, and time. The project came to mind a few years ago as a good project to
learn Go and React, but ended up including Docker, Terraform, and even more than that.

As for running user submitted code for the Bytegolf application, I leveraged the
[Jdoodle Compiler API](https://docs.jdoodle.com/integrating-compiler-ide-to-your-application/compiler-api).
However I decided having an in-house solution to customize the languages and
versions that I would want to support would be better for the long term, and thus
the Bytegolf Compiler was born.

## Architecture

<p align="center">
  <img src="https://img.squwid.dev/zsxaQONoui.png" alt="Bytegolf Compiler Architecture">
</p>

The Bytegolf Compiler is run as a singleton web server that runs on the **same level**
as Docker. Although it doesn't need to run on bare-metal, it is recommened to 
avoid nested virtualization. To run the Bytegolf Compiler within a Docker
container on the Host, Docker would have to be exposed to the container using
some [Docker-in-Docker (DinD)](https://www.docker.com/blog/docker-can-now-run-within-docker/) solution.

The goal was to avoid running untrusted code in VMs, but instead leverage 
ephemeral Docker containers to run the code for a quicker turnaround and
less configuration.

### Container Security

Running untrusted code in Docker containers can be a security risk. [gVisor](https://gvisor.dev/docs/),
a Google-developed application kernel, acts as a security shield between the 
container and host operating system, significantly reducing that risk.

After gVisor installation, the `runsc` binary is available to be used as a runtime for
Docker by configuring the Docker daemon `/etc/docker/daemon.json`. I wanted
to ensure there was no network access for the untrusted user containers, which
gVisor luckily supports with the following Docker daemon config.

```json
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc",
      "runtimeArgs": [
         "--network=none"
      ]
    }
  }
}

```

## Usage

### Compiler Web Server

The webserver acts as a front door for code "Submissions". The compiler 
is wrapped in a CLI allowing for the following to be configured:

| Flag | Default | Description |
|---|---|---|
| `backlog`| 2000 | Job backlog before API rejects requests. |
| `memory` | 512 | Amount of memory that a container can use for a single run (in MB). |
| `cpu` | 1024 | CPU shares for a container. |
| `output` | 30 | Number of bytes that can be read from a container output before the container is killed (in KB). |
| `timeout` | 30 | Container timeout in seconds. |
| `workers` | 4 | Number of concurrent workers. |
| `port` | 8080 | Port to run the compiler on. |
| `--gvisor` | false | Use [gVisor](https://gvisor.dev/) for increased container security (requires runsc). |

#### Workers

Let's focus on the "Worker"s for a second. A "Worker" in this context is
a Go routine that listens for "Jobs" on a channel. Each worker is responsible
for creating a new Docker container with the requested image, starting the
container, collecting StdOut/StdErr streams, and cleaning up the container
once it has completed. Each worker is configured with CPU shares and memory limits
for right-sizing. For more detailed information about CPU shares, see the
[CPU Shares for Docker Containers](https://batey.info/cgroup-cpu-shares-for-docker.html)
blog by Christopher Batey.

For example, running the binary on a system with 8GB of Ram, 4 Cores, with 8
threads could comfortably fit 7 workers with 1GB of memory and 1024 CPU shares
each. 

```bash
bg-compiler start --workers 7 --cpu 1024 --memory 1024
```

For less CPU intense scripts, the CPU could be decreased to 512 or 256, and 
multiple containers could run on the same thread.

#### Submission to Jobs

When a user submits a code snippet to the `/compile` endpoint, the compiler
takes this in as a "Submission", writing the `script` to a tmp directory on
the host. The compiler takes this tmp directory, and generates a single read-only
[Docker bind mount](https://docs.docker.com/storage/bind-mounts/).

The compiler then creates `count` "Jobs" for each submission, which atomic
input to a "Worker". Once all Jobs are processed and completed, the compiler
will return the results as a list to the client.

For example, lets say I want to take the following python code and run it 3 times:

```python
import random

random_number = random.randint(1, 1000000)
print(random_number) 
```

The code needs to be HTML escaped and sent as the `script` field of a
JSON object to the `/compile` endpoint.

{{< alert "secondary" >}}
The host machine must have the Docker daemon running and the container image
requested present for a compile request. In this case, `python:3.11.1-alpine3.17`
would need available on the host.
{{< /alert >}}


```bash
curl --request POST \
  --url http://localhost:8080/compile \
  --header 'Content-Type: application/json' \
  --data '{
	"script": "import random\nrandom_number = random.randint(1, 1000000)\nprint(random_number)",
	"image": "python:3.11.1-alpine3.17",
	"count": 3,
	"cmd": "python3"
}'
```

Behind the scenes the `script` gets mounted to each container as `/bg/main.ext`,
and each container runs `{cmd} /bg/main.ext` where `{cmd}` is the command
passed in the `cmd` field of the JSON object.


The output of running this command would be:

```json
[
  {
    "stdout": "947257\n",
    "stderr": "",
    "duration_ms": 188,
    "timed_out": false
  },
  {
    "stdout": "388874\n",
    "stderr": "",
    "duration_ms": 211,
    "timed_out": false
  },
  {
    "stdout": "956220\n",
    "stderr": "",
    "duration_ms": 191,
    "timed_out": false
  }
]
```

## Next Steps

Overall, this project was a fun way to explore the depths of Docker and Go. 
It meets all of the curret needs for the Bytegolf project, but there are a few
things that I would consider adding if I had more time in the future:

- Allowing the compiler to pull images from Dockerhub when they are unavailable.
- Allow for multiple code files as input to a worker.
- Non-singleton architecture for scaling, using some PubSub or Redis for queuing.
- Make the `POST` body the entire code block, rather than require HTML escaping into JSON.
