# Getting the Container

## Software and storage requirements

You need one of the container engines pre-installed on the host system:
[Docker](https://www.docker.com), [Podman](https://podman.io), or
[Apptainer](https://apptainer.org/) (formerly Singularity). Podman is a
drop-in, daemonless, rootless-by-default replacement for Docker that
uses the same commands as Docker. The container is approximately 19 GB.

## Option A — Pull from Docker Hub

::::{tab-set}

:::{tab-item} Docker
`````bash
docker pull cvriend/tractoprep:{{RELEASE_TAG}}
`````
:::

:::{tab-item} Podman
`````bash
podman pull docker://cvriend/tractoprep:{{RELEASE_TAG}}
`````
:::

:::{tab-item} Apptainer
`````bash
apptainer pull docker://cvriend/tractoprep:{{RELEASE_TAG}}
`````
:::

::::

```{note} 
docker and pullman will automatically pull the container on the first run if it is not yet available and the server has an internet connection. A separate pull is therefore not mandatory
```

## Option B — Direct .sif download (Apptainer)

A pre-built Singularity Image Format (`.sif`) file is available for
direct download, for sites without internet/registry access on their
compute cluster.

**Download location:**

```bash
wget https://surfdrive.surf.nl/s/6Q6NxYxKyWqSHj7/download
```

Copy the resulting `.sif` file to your compute cluster.
