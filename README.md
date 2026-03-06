# Local mirror for CentOS Stream & EPEL

Creates local mirrors of the CentOS Stream & EPEL repositories and stores them as container images to keep an history and optimize storage consumption.

## Usage

Create & serve the mirror.

```sh
# Create a local mirror of CentOS Stream 10
./build.sh

# Serve the mirror on port 8080
podman run --rm --name mirror-centos-stream-10-$(date -I) -p 8080:8080 localhost/mirrors/centos-stream-10:$(date -I)

# Mirror is alive!
curl http://localhost:8080/centos/10-stream/BaseOS/x86_64/iso/SHA256SUM

# Archive the mirror for posterity
podman tag localhost/mirrors/centos-stream-10:$(date -I) quay.io/nmasse-redhat/centos-stream-10:$(date -I)
podman push --compression-format=none quay.io/nmasse-redhat/centos-stream-10:$(date -I)
```

To use it in a working system, create `/etc/yum.repos.d/local-mirror.repo` with the following content:

```ini
[local-centos-stream]
name=Local CentOS Stream $releasever
baseurl=http://local.mirror.tld:8080/centos/10-stream/BaseOS/$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official

[local-epel]
name=Local EPEL $releasever
baseurl=http://local.mirror.tld:8080/epel/10/Everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10
```

To perform an unattended install, add the following lines in your kickstart file:

```
url --url=http://local.mirror.tld/centos/10-stream/BaseOS/$basearch/os/
repo --name=epel --baseurl=http://local.mirror.tld:8080/epel/10/Everything/$basearch/
```

## Authors

- Claude Code
- Nicolas Massé
