# Debian 13 KVM on Suga

A GitHub-deployable QEMU/KVM Debian 13 (Trixie) VM container with a browser serial console (ttyd), cloud-init first-boot setup, persistent VM storage, and SSH port forwarding.

## Important: KVM support is conditional

Suga deploys standard containers. A Dockerfile alone cannot grant a container access to the host hypervisor. **Hardware KVM acceleration works only if Suga allows `/dev/kvm` device passthrough and the required permissions.** This project checks for `/dev/kvm`:

- If accessible: QEMU uses KVM acceleration.
- If unavailable: QEMU falls back to TCG software emulation. This can be very slow and may be unsuitable for a usable VPS.

Do not assume that a successful container deployment means nested KVM is enabled. If Suga does not expose `/dev/kvm`, ask Suga support whether device passthrough / nested virtualization is supported on your plan. Do not try to bypass the platform's isolation.

## Deploy on Suga

1. Push this repository to GitHub.
2. In Suga, create a project/environment and add a service from the GitHub repository.
3. Build from the repository root (the included `Dockerfile` is detected automatically).
4. Set the service's HTTP port to `8080` (or set `PORT` to the port Suga assigns).
5. Attach a **persistent volume** mounted at `/data`. The Debian VM disk and downloaded base image are stored there.
6. Add the environment variables below. Use strong, unique passwords.
7. Deploy and open the service's HTTPS URL.

### Required environment variables

| Variable | Example | Purpose |
|---|---|---|
| `VM_PASSWORD` | Generate your own | Linux password for the guest user |
| `TTYD_PASSWORD` | Generate another | Browser terminal HTTP Basic Auth password |
| `TTYD_USERNAME` | `sam` | Browser terminal username |

### Optional environment variables

| Variable | Default | Purpose |
|---|---:|---|
| `PORT` | `8080` | Browser terminal HTTP port |
| `VM_NAME` | `debian13` | Guest hostname |
| `VM_RAM` | `2048` | Guest RAM in MiB |
| `VM_CPUS` | `2` | Guest vCPU count |
| `VM_DISK_SIZE` | `20G` | Initial virtual disk capacity |
| `VM_USERNAME` | `sam` | Guest Linux username |

**Resource note:** VM RAM and CPU are allocated inside the container's Suga resource limits. Leave room for QEMU and the terminal process. A 2 GiB guest needs more than 2 GiB available to the container.

## Browser terminal

Open the Suga HTTPS URL and authenticate using `TTYD_USERNAME` and `TTYD_PASSWORD`. The terminal connects to the Debian guest's serial console. Log in with `VM_USERNAME` and `VM_PASSWORD` after cloud-init completes; first boot can take a few minutes.

## SSH

QEMU forwards guest SSH port 22 to container port `2222`. If Suga supports public TCP services, expose container TCP port `2222` and connect using:

```bash
ssh -p YOUR_PUBLIC_TCP_PORT sam@YOUR_SUGA_TCP_HOST
```

If Suga does not offer a public TCP mapping for this service, use the browser terminal instead. Do not expose SSH without using a strong guest password or, preferably, SSH keys.

## Persistence and reset

The `/data` volume stores:
- `debian-13-genericcloud-amd64.qcow2` (verified Debian base image)
- `debian13.qcow2` (your writable VM disk)
- `debian13-seed.iso` (cloud-init configuration)

Redeploys should retain the guest when the same persistent volume remains attached. To reset the guest, stop the service and delete `debian13.qcow2` and `debian13-seed.iso` from the volume; the next start recreates it. Back up the disk before doing this.

## Local build

```bash
docker build -t suga-debian13-kvm .
docker run --rm -it \
  --device /dev/kvm \
  -p 8080:8080 \
  -p 2222:2222 \
  -v debian13-data:/data \
  -e VM_PASSWORD='replace-this' \
  -e TTYD_PASSWORD='replace-this-too' \
  suga-debian13-kvm
```

For software emulation only, omit `--device /dev/kvm` (expect very low performance).

## Security

- Browser terminal is protected by ttyd HTTP Basic Authentication.
- The guest's default user has passwordless sudo for administration. Protect the terminal credentials carefully.
- Change both default passwords by setting Suga environment variables; the container refuses to start with the example defaults.
- Keep `/data` private and back it up.
- This is a single-VM lab setup, not a hardened multi-tenant virtualization host.
