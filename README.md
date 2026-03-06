# Local mirror for CentOS Stream & EPEL in a container image

Creates local mirrors of the CentOS Stream & EPEL repositories and stores them as container images to keep an history and optimize storage consumption.

## Usage

Create & serve the mirror.

```sh
# Pre-requisites
sudo dnf install -y podman buildah skopeo curl lorax

# Create a local mirror of CentOS Stream 10
sudo ./build.sh

# Serve the mirror on port 8080
sudo podman run -d --rm --name mirror-centos-stream-10-$(date -I) -p 8080:8080 localhost/mirrors/centos-stream-10:$(date -I)

# Mirror is alive!
curl http://localhost:8080/centos/10-stream/BaseOS/x86_64/iso/SHA256SUM

# Archive the mirror for posterity
sudo podman save --output centos-stream-10-$(date -I) --format oci-dir --uncompressed localhost/mirrors/centos-stream-10:$(date -I)
sudo podman tag localhost/mirrors/centos-stream-10:$(date -I) quay.io/nmasse-redhat/centos-stream-10:$(date -I)
sudo buildah push --disable-compression quay.io/nmasse-redhat/centos-stream-10:$(date -I)

# Install a VM from this mirror using Kickstart
sudo mkdir -p /var/lib/libvirt/images/test-centos10
sudo curl -sSfL -o /var/lib/libvirt/images/test-centos10/CentOS-Stream-10-latest-x86_64-boot.iso  http://dev-aarch64.itix.fr/centos/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-boot.iso
sudo mkksiso -R 'set timeout=60' 'set timeout=5' -R 'set default="1"' 'set default="0"' -r console -c console=ttyS0 --ks "kickstart.cfg" /var/lib/libvirt/images/test-centos10/CentOS-Stream-10-latest-x86_64-boot.iso /var/lib/libvirt/images/test-centos10/install.iso
sudo virt-install --name test-centos10 --memory 4096 --vcpus 2 --disk path=/var/lib/libvirt/images/test-centos10/root.qcow2,format=qcow2,bus=virtio,size=100 --cdrom /var/lib/libvirt/images/test-centos10/install.iso --network network=default --console pty,target_type=virtio --serial pty --graphics none --os-variant rhel10-unknown --boot uefi

# Cleanup the VM
sudo virsh destroy test-centos10
sudo virsh undefine test-centos10 --nvram
sudo rm -f /var/lib/libvirt/images/test-centos10/root.qcow2 /var/lib/libvirt/images/test-centos10/install.iso
```

To use it in a working system, create `/etc/yum.repos.d/local-mirror.repo` with the following content:

```ini
[local-centos-stream]
name=Local CentOS Stream $releasever
baseurl=http://local.mirror.tld:8080/centos/10-stream/BaseOS/$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256

[local-epel]
name=Local EPEL $releasever
baseurl=http://local.mirror.tld:8080/epel/10/Everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10
```

To perform an unattended install, see the supplied [kickstart script](kickstart.cfg).

## Numbers

CentOS 10 BaseOS + EPEL 10, x86_64 only, no source, no debug RPM, takes about 32 minutes to synchronize and uses 44 GB on disk.

## Authors

- Claude Code
- Nicolas Massé
