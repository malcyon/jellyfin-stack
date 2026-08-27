# Windows 11 test VM

A throwaway Windows 11 Enterprise (evaluation) VM with WinUAE and VICE, running under
QEMU/KVM + libvirt on **this workstation** (`home`), driven from Ansible.

It is a **separate playbook** from `playbook.yml` on purpose — rebuilding the
test VM should never touch the media stack, and vice versa. It targets the
`winvm_hosts` group, which currently contains only `workstations`.

```
virt-manager (SPICE console, local)
        │
        ▼
   win11 guest ── 192.168.123.50 ── virbr-win ──NAT──> LAN
                       ▲
                  RDP :3389 direct, no forwarding needed
```

> **History:** this first ran on the media server, where the VM had to be
> reached over RDP through a `socat` forward. It now runs locally, so the
> console is direct and `winvm_forwarded_ports` is empty. The role still
> supports the remote case — see *Running it on a remote host* below.

---

## Step 1 — Windows ISO

Microsoft's Evaluation Center gates the download behind a registration form, so
there is no stable URL Ansible can fetch. Download the **64-bit English ISO**
from
<https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise>
and point `winvm_iso_src` at it in
`ansible/group_vars/workstations/vars.yml`. The playbook copies it into place.

The evaluation runs 90 days. When it expires, tear down and rebuild:

```bash
ansible-playbook -i ansible/inventory.yml ansible/windows-vm-teardown.yml
ansible-playbook -i ansible/inventory.yml ansible/windows-vm.yml
```

## Step 2 — Add the guest password to the vault

```bash
ansible-vault edit ansible/group_vars/workstations/vault.yml
```

```yaml
vault_windows_admin_password: <something Windows will accept>
```

Windows rejects weak passwords during unattended setup — 8+ characters with
three of upper / lower / digit / symbol.

## Step 3 — Run the playbook

```bash
ansible-playbook -i ansible/inventory.yml ansible/windows-vm.yml
```

It installs QEMU/libvirt/swtpm, creates the NAT network and the domain, builds
the `autounattend.xml` ISO, and installs the RDP forwarder. It does **not**
start the VM.

## Step 4 — Install Windows

```bash
sudo virsh start win11 && \
  for i in $(seq 1 15); do sudo virsh send-key win11 --codeset linux KEY_ENTER; sleep 1; done
```

The keypress loop is not optional on the **first** boot. The blank disk has no
EFI boot entry, so the firmware falls through to the DVD — and Microsoft's
`efisys.bin` then puts up *"Press any key to boot from CD or DVD"* and waits.
With nobody at the console it lapses and drops you into the firmware boot
manager. Fifteen Enters over fifteen seconds covers the window.

**Stop pressing keys after that.** Once WinPE loads, stray keypresses land on
Setup's UI and click through screens that `autounattend.xml` is trying to
answer — which looks exactly like the unattend being ignored.

Later boots need none of this: Windows is then first in the boot order and the
DVD is never reached.

From there Setup runs unattended — disk partitioning, OOBE, your local account,
RDP, the static IP, and the firewall rules all come from `autounattend.xml`.
Expect roughly 15–25 minutes including reboots. Watch progress without touching
anything:

```bash
sudo virsh screenshot win11 /tmp/w.png && xdg-open /tmp/w.png
```

Or just open the SPICE console in `virt-manager`.

Watch it if you want — the SPICE console is local:

```bash
virt-manager
```

## Step 5 — Use it

> **First time only:** the playbook adds you to the `libvirt` group, but Linux
> grants group membership at login, so a desktop session opened beforehand
> still lacks it. virt-manager then fails with *"Unable to connect to libvirt
> qemu:///system — verify that the 'libvirtd' daemon is running"*, which is
> misleading: the daemon is running, your session just cannot open
> `/var/run/libvirt/libvirt-sock` (mode 0660, group `libvirt`).
>
> Log out and back in to fix it permanently. To use it immediately without
> logging out:
>
> ```bash
> sg libvirt -c virt-manager
> ```
>
> Check with `groups | grep libvirt` — if that is empty, this is your problem.


| Goal | Command |
|---|---|
| Console — audio, works before networking | `virt-manager` → double-click `win11` |
| Console, straight to the VM | `virt-viewer --connect qemu:///system win11` |
| Full desktop, drive redirection | `xfreerdp /v:192.168.123.50 /u:donald /cert:ignore /sound` |
| Run one command in the guest | `winvm ssh 'Get-Date'` |
| Copy a file in | `scp game.adf donald@192.168.123.50:C:/Amiga/` |
| See the screen from a script | `winvm shot /tmp/win11.png` |
| Start/stop from an agent | `winvm acquire <tag>` / `winvm release <tag>` |

**SPICE console (simplest).** The VM is on this machine, so no networking is
involved and it works before Windows has finished configuring itself:

```bash
virt-manager            # or: virt-viewer --connect qemu:///system win11
```

SPICE carries audio, which is why it is used instead of VNC — WinUAE is not
much use mute. The domain has an ICH9 HD Audio device, which Windows drives
with its in-box driver.

**RDP**, if you want a resizable desktop and drive redirection:

```bash
xfreerdp /v:192.168.123.50 /u:donald /cert:ignore /dynamic-resolution \
         /clipboard /sound /drive:dev,/home/donald/src
```

Leave `/p:` off so it prompts rather than putting the password in your shell
history. Note the address is the guest directly — no port forwarding, because
the VM is local.

> **FreeRDP 2 vs 3.** Pop!_OS 24.04 ships FreeRDP 2 as `xfreerdp`, and it is
> creaky against 25H2 — `Timeout waiting for activation` after a successful
> NLA handshake is the usual symptom, especially when the console session is
> already logged in as the same user. `sudo apt install freerdp3-x11` gives
> you `xfreerdp3`, which handles it properly. Remmina (already installed) uses
> the FreeRDP 3 libraries and is another way around it.
>
> A plain `STATUS_LOGON_FAILURE` is something else entirely: that is just a
> wrong password.

## WinUAE

Installed automatically at first logon from the unattend ISO — no download
needed in the guest — to `C:\Program Files\WinUAE`, and that directory is
excluded from Defender real-time scanning.

**You still need Kickstart ROMs.** WinUAE ships none: they are copyrighted and
come from Amiga Forever, or dumped from hardware you own. Put them wherever you
like and add that directory to `winvm_defender_exclusions`, then re-run the
playbook — real-time scanning of ADF/HDF images is what actually hurts
performance:

```yaml
winvm_defender_exclusions:
  - 'C:\Program Files\WinUAE'
  - 'C:\Amiga'
```

Exclusions are applied at first logon, so changing them means a rebuild. To add
one to a running VM, in an elevated PowerShell inside the guest:

```powershell
Add-MpPreference -ExclusionPath 'C:\Amiga'
```

## Display — the QXL driver

`virtio-win-gt-x64.msi` installs the network, storage and balloon drivers but
**not** the display one. Without the QXL driver the guest runs on *Microsoft
Basic Display Adapter*: one fixed mode, no taller resolutions offered, and no
SPICE auto-resize when you resize the viewer window.

That is worse than cosmetic. A dialog taller than the screen has its buttons
off the bottom edge with nothing to drag them back with — which is how this was
found, in 2026-08, with VICE's disk-attach dialog in 1280x800.

`guest-setup.ps1` now installs it with `pnputil` from the virtio ISO. Two things
about that step are deliberate:

* **It runs after the virtio MSI**, which puts Red Hat's certificate in the
  TrustedPublisher store. Without that certificate `pnputil` waits for a human
  to confirm the publisher, on a machine with nobody at it.
* **The path is the `w10` package.** The ISO carries no `w11` build of
  `qxldod`; `w10\amd64` is the Windows 11 one.

```yaml
winvm_install_qxl: true
winvm_qxl_inf: 'qxldod\w10\amd64\qxldod.inf'
```

On a VM built before this existed, install it by hand from the attached virtio
volume and reboot:

```powershell
pnputil /add-driver E:\qxldod\w10\amd64\qxldod.inf /install
```

Check with `(Get-CimInstance Win32_VideoController).Name` — *Red Hat QXL
controller* rather than *Microsoft Basic Display Adapter*.

## VICE

Installed automatically at first logon from the unattend ISO, the same as
WinUAE and for the same reason — first logon needs no working internet. It
lands in `C:\VICE`, and that directory is excluded from Defender real-time
scanning.

**It is unpacked rather than installed.** VICE ships a zip and no installer, so
there is nothing for `msiexec` to do; `guest-setup.ps1` expands it instead, and
the log at `C:\Windows\Temp\guest-setup.log` carries the result under
`install VICE`.

**The version is flattened out of the path.** The archive holds a single
top-level directory named for the release — `GTK3VICE-3.10-win64` — so
unpacking it as-is would put the emulator at a path that moves with every VICE
release. The unpack step lifts that directory's contents up one level, so the
binary is at a stable path:

```
C:\VICE\bin\x64sc.exe
```

Upgrading is therefore two lines in `roles/windows-vm/defaults/main.yml` and a
rebuild — nothing that names the path has to change:

```yaml
winvm_vice_url: https://downloads.sourceforge.net/project/vice-emu/releases/binaries/windows/GTK3VICE-3.10-win64.zip
winvm_vice_zip: GTK3VICE-3.10-win64.zip
```

Set `winvm_install_vice: false` to skip it.

**The binary monitor is not enabled for you.** VICE's remote monitor is what
`wish`'s automapper attaches to, and it is off by default. Turn it on inside the
guest — Settings → Machine → Monitor, or `-binarymonitor` on the command line.
Automating it would mean writing the guest's `vice.ini` from here, which nothing
has needed yet.

## VICE settings and the JiffyDOS ROMs

`templates/vice.ini.j2` is rendered on the host and copied into
`C:\Users\<user>\AppData\Roaming\vice\vice.ini` at first logon. It mirrors
the workstation's own `~/.var/app/net.sf.VICE/config/vice/vicerc`, minus the
host paths, so a measurement taken in the VM is comparable with one taken here.

**It is written only if absent.** VICE keeps `SaveResourcesOnExit=1`, so once
somebody has opened the settings dialog the file on disk is theirs; overwriting
it on a later run would discard their work.

Two settings in it are the point of seeding it at all:

* `VICIIFilter=0` — no rendering filter, which is what turns CRT emulation and
  its scan lines off.
* `BinaryMonitorServer=1` on `127.0.0.1:6502` — the socket `wish`'s automapper
  attaches to, off in a stock VICE. **The resources are `BinaryMonitorServer`
  and `BinaryMonitorServerAddress`.** There is no `BinaryMonitor` resource;
  setting that name does nothing at all, silently.

**The JiffyDOS ROMs are copyrighted**, so they live in `work/jiffydos/` here,
which `.gitignore` excludes, and ride the unattend ISO into
`C:\C64\JiffyDOS` — the same reasoning as the Kickstart ROMs, which stay
outside the repository altogether. That directory is excluded from Defender too.

Set `winvm_jiffydos_src: ""` to skip them. VICE then uses the stock kernal,
which works — it just has no fastloader, and Pool of Radiance asks to disable
its own on boot.

```yaml
winvm_jiffydos_src: "{{ playbook_dir }}/../work/jiffydos"
winvm_jiffydos_dest: 'C:\C64\JiffyDOS'
winvm_vice_binary_monitor: true
winvm_vice_binary_monitor_port: 6502
```

## Day-to-day — the `winvm` command

`/usr/local/bin/winvm` is installed by the playbook and is the intended way to
drive the VM, by hand or from a script. Every state-changing command takes an
`flock`, so concurrent callers serialise instead of racing.

| Command | What it does |
|---|---|
| `winvm status` | State, golden base size, overlay size, and who holds leases |
| `winvm up` | Start (or restore a saved state) and block until ssh answers |
| `winvm down` | Graceful shutdown; force-off after 2 minutes if it hangs |
| `winvm save` | `managedsave` — suspend to disk; `up` then resumes in seconds |
| `winvm acquire <tag>` | Take a named lease and start the VM if it is not up |
| `winvm release <tag>` | Drop that lease; shuts down only when the last one goes |
| `winvm promote` | Flatten the current disk into the golden base (one-off, after install) |
| `winvm revert` | Throw away everything since golden — about a second |
| `winvm shot [file]` | Framebuffer screenshot; works regardless of session state |
| `winvm ssh [cmd...]` | ssh into the guest as `donald` |

### Leases, for multiple agents

`up`/`down` are fine for one caller. With several agents sharing the VM they
race — agent A calls `down` while agent B is mid-test. Leases fix that by
reference counting:

```bash
winvm acquire re-session-1     # starts it if needed
winvm acquire fuzz-run-7       # no-op, already up
winvm release re-session-1     # still held by fuzz-run-7 — stays up
winvm release fuzz-run-7       # last lease gone — shuts down
```

Leases are files in `/var/lib/libvirt/winvm/leases`. A crashed agent leaves a
stale one behind; `winvm status` lists them and `rm` clears them.

### Reverting to a clean state

**libvirt snapshots do not work on this VM** — Windows 11 requires UEFI, and:

```
error: Operation not supported: internal snapshots of a VM
       with pflash based firmware are not supported
```

So the role uses a qcow2 overlay instead. After the install finishes, freeze it
once:

```bash
winvm down
winvm promote        # win11.qcow2 -> win11-golden.qcow2 + a fresh overlay
```

From then on the VM runs from a thin overlay on that immutable base, and

```bash
winvm revert
```

deletes the overlay, recreates it, and restores the UEFI varstore from its
golden copy. That last part matters: reverting the disk without the NVRAM can
leave a boot entry pointing at an ESP that no longer exists.

To adopt the current state as the new baseline — say after installing a
debugger you want in every session — delete the golden file and re-promote:

```bash
winvm down && sudo rm /var/lib/libvirt/winvm/win11-golden.qcow2 && winvm promote
```

### Raw virsh equivalents

`winvm` is a wrapper; nothing stops you using libvirt directly. Without the
`libvirt` group in your session these need `sudo` (see Step 5).

| | |
|---|---|
| Start / graceful stop / force off | `virsh start\|shutdown\|destroy win11` |
| State | `virsh list --all` |
| Guest IP (needs the guest agent) | `virsh domifaddr win11 --source agent` |
| Console | `virt-viewer --connect qemu:///system win11` |

The VM does **not** autostart — 6 GiB is a lot to hold idle on a 15 GiB
desktop. Set `winvm_autostart: true` if you would rather it came up at boot.

Once Windows is installed, detach the unattend ISO so the plaintext password
stops riding along with the VM:

```bash
sudo virsh change-media win11 sdd --eject --config
```

## Forwarding extra ports

To reach a dev server inside the VM from `home.lan`, add to
`ansible/group_vars/media_servers/vars.yml`:

```yaml
winvm_forwarded_ports:
  - { name: rdp,       port: 3389 }
  - { name: devserver, port: 5173 }
```

Re-run the playbook. Each entry gets a `socat` systemd unit on the host and an
inbound Windows Firewall rule in the guest (the guest rules are applied by
`autounattend.xml`, so ports added later need adding by hand inside Windows —
or rebuild the VM).

---

## Why it is built this way

**A dedicated `winvm` NAT network with no DHCP, not libvirt's `default`.**
Pi-hole runs with `network_mode: host` and is the LAN's DNS *and* DHCP server,
holding `0.0.0.0:53` and `0.0.0.0:67`. libvirt's `default` network starts a
dnsmasq that wants both and fails outright. A DHCP server always binds the
wildcard address — there is no way to scope one to a single interface — so a
second DHCP server on this host is simply not possible.

So `winvm` (on `192.168.123.0/24`) declares neither DNS nor DHCP, and libvirt
starts **no dnsmasq for it at all** — it only creates the bridge and the NAT
rules. The guest addresses itself statically from `autounattend.xml`, and is
pointed at Pi-hole for DNS so it can resolve `*.morton.lan`. The playbook also
stops and un-autostarts libvirt's `default` network, which would hit the same
wall on every boot.

**`socat` units, not DNAT rules.** Docker and Tailscale both rewrite iptables on
this host. A userspace forwarder cannot be reordered out of existence by either.

**libvirt pinned to the iptables firewall backend.** Docker sets
`iptables -P FORWARD DROP`. libvirt's default nftables backend writes ACCEPT
rules into its own nft table, which cannot override that policy, and the VM
ends up with no outbound network. `/etc/libvirt/network.conf` pins it to the
iptables backend so its rules land at the top of the same chain Docker uses.

**SATA disk and an e1000e NIC, not virtio.** Both have in-box Windows drivers,
so nothing has to be injected into WinPE — driver paths in WinPE depend on
unpredictable drive letters and are the most common cause of a failed
unattended install on KVM. The virtio ISO is still attached, and the QEMU guest
agent is installed from it on first logon. Switch the disk to `virtio` in
`templates/winvm-domain.xml.j2` later if you want the throughput.

**LabConfig bypasses in `autounattend.xml`.** The VM has a real emulated TPM 2.0
and Secure Boot, so those checks would pass — but the host is an i7-4790
(Haswell) and Windows 11 Setup only accepts 8th-gen and newer processors. The
`BypassCPUCheck` key is what gets Setup past that; the others are set alongside
it so the install does not stall if firmware features come up differently.

**The guest agent needs two installers, not one.** The agent talks to the host
over virtio-serial, for which Windows has no in-box driver — and this VM
otherwise needs none, since it boots on SATA and e1000e. On the virtio-win ISO
the pieces are split:

| installer | what it actually provides |
|---|---|
| `guest-agent\qemu-ga-x86_64.msi` | the `QEMU-GA` service, and nothing else |
| `virtio-win-gt-x64.msi` | 13 drivers including `vioser.sys`, and **no agent** |

Install the agent alone and you get a service with no channel; install the
drivers alone and you get a channel with no service. Both fail identically from
the host — `state='disconnected'`. First logon installs both. Verify with:

```bash
sudo virsh dumpxml win11 | grep guest_agent    # want state='connected'
sudo virsh domifaddr win11 --source agent
```

**UTC hardware clock, pinned on both sides.** The domain sets
`<clock offset='utc'/>` and first logon sets `RealTimeIsUniversal=1`. With
`localtime` the guest clock slipped by exactly the timezone offset once Windows
started syncing time; `localtime` also misbehaves across DST transitions.
Setting only one side reintroduces the same skew, so change both or neither.

**The guest's static IP is set by adapter index, not adapter name.** `netsh`
and PowerShell both address adapters as "Ethernet" by default, which is a
localised string. `Get-NetAdapter -Physical | Select-Object -First 1` works
whatever the image language is. If you change `winvm_ip`, `winvm_net_prefix`,
`winvm_net_gateway`, or `winvm_dns_server`, the guest only picks the new values
up on a rebuild — they are applied once, at first logon.

---

## Troubleshooting

**Sitting at "Press any key to boot from CD or DVD", or at a boot-device
menu.** The keypress window was missed — see Step 4. If you are at the boot
menu, pick **UEFI QEMU DVD-ROM QM00003** (that is `sdb`, the Windows ISO;
`QM00005` and `QM00007` are the virtio and unattend ISOs and are not bootable),
then send Enter again for the "press any key" prompt that follows.

**Setup shows its normal interactive screens.** Almost always stray keypresses
rather than a broken unattend — a key sent after WinPE has loaded clicks
whatever button has focus. Destroy the VM, recreate the disk, and retry
hands-off:

```bash
sudo virsh destroy win11; sudo rm -f /var/lib/libvirt/winvm/win11.qcow2
ansible-playbook -i ansible/inventory.yml ansible/windows-vm.yml
```

If it genuinely is being ignored, note that Windows 11 24H2 introduced a new
setup engine ("ConX", `SetupPrep.exe`) with reported unattend regressions; the
usual workaround is forcing the legacy path with a `winpeshl.ini` in `boot.wim`
calling `setup.exe /legacy`. This image (25H2, build 26200.6584) does **not**
need that — it drops to legacy setup on its own once `autounattend.xml` is
found.

**"Windows cannot be installed to this disk".** The eval ISO shipped more than
one image. Check the indexes and set `winvm_image_index`:

```bash
sudo mkdir -p /mnt/winiso && sudo mount -o loop,ro \
  /var/lib/libvirt/winvm/iso/windows11-enterprise-eval.iso /mnt/winiso && \
  sudo wiminfo /mnt/winiso/sources/install.wim | grep -E "^Index|^Name"
```

**RDP refuses the connection.** Confirm the VM is up and has its address, then
that the forwarder is running:

```bash
sudo virsh domifaddr win11 --source agent; sudo virsh domstate win11
```

**No internet inside the guest.** Almost always the Docker `FORWARD DROP`
interaction. Confirm the backend is pinned and libvirt reloaded:

```bash
grep firewall_backend /etc/libvirt/network.conf; sudo iptables -S FORWARD | head
```

**The guest has no address at all.** There is no DHCP on this network by
design, so the address comes from the first-logon script. Check it from the
console (`virsh net-list` should show `winvm` active and `virbr-win` holding
192.168.123.1), then inside Windows:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress
```

If it is empty or shows a 169.254.x.x autoconfiguration address, re-run the
static configuration by hand — the command is in
`/home/vms/state/unattend/autounattend.xml` on the server.

**Setup stops on a compatibility screen.** Press `Shift+F10` for a console and
check that `HKLM\SYSTEM\Setup\LabConfig` actually has the bypass values — that
means the unattend ISO was not picked up, usually because it is not attached.

---

## Removing it

```bash
ansible-playbook -i ansible/inventory.yml ansible/windows-vm-teardown.yml
```

Destroys and undefines the domain (with `--nvram`, or libvirt refuses and
orphans the UEFI varstore), removes the network, the socat units, the whole
`winvm_base_dir` tree, the AppArmor override, and the `firewall_backend` pin.

It deliberately **leaves the QEMU/libvirt packages installed** — pulling ~99
packages off a host is a bigger blast radius than removing a VM. To finish the
job by hand:

```bash
sudo apt purge --autoremove qemu-system-x86 libvirt-daemon-system swtpm
```

On the media server it also leaves libvirt's `default` network defined but not
autostarting. That is intentional: starting it would put libvirt's dnsmasq back
in contention with Pi-hole for :53 and :67.

---

## Running it on a remote host

The role still supports a VM on another machine — that is how it started. Put
the host in `winvm_hosts` and set, in its group_vars:

```yaml
winvm_graphics: vnc            # loopback only; reach it over an SSH tunnel
winvm_forwarded_ports:         # one socat unit each, on the VM's host
  - { name: rdp, port: 3389 }
winvm_disable_default_network: true    # only if something else owns :53/:67
winvm_base_dir: /home/vms      # if the root filesystem is too small
```

Then RDP to *that host's* address on 3389 and the socat unit relays to the
guest. `socat` is used rather than DNAT rules because Docker and Tailscale both
rewrite iptables, and a userspace forwarder cannot be reordered out of
existence by either.

Console access is then:

```bash
ssh -L 5900:127.0.0.1:5900 <host>
vncviewer localhost:5900
# or, for the full GUI:
virt-manager -c qemu+ssh://donald@<host>/system
```
