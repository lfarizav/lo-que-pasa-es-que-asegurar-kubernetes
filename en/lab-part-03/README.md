# Part III - Lab: a uniform that takes system calls away, a padlock cut to the shape of the shop, a storeroom you may read but never write in, and a yard somebody opened a back exit onto

- Time: 60 min
- Points: 40

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the command sequence that solves it lives in that step's cmd field for you to reveal after trying it with your own hands. Step 1 puts the regulation uniform on the guard, seccompProfile RuntimeDefault, and demands you prove that uniform genuinely takes system calls away: beside him stands a twin guard with no uniform that the setup left in place, and grading compares the two live, so deleting the twin or dressing him too loses the step. Step 2 orders a padlock cut to measure: your own seccomp profile, written in JSON and installed on the node's disk, which lets the container work but forbids it one specific family of calls; grading walks into the node to read the profile file, so deleting it once the Pod is up fails the step. Step 3 goes down to the storeroom yard with AppArmor: you load a deny-write profile onto the node and attach it to the Pod through the appArmorProfile field, and grading does not believe the manifest, it asks the live process which profile it runs under and in which mode, so loading it in complain or setting type Unconfined fails no matter how pretty the YAML looks. Step 4 hands you the yard with a back exit somebody opened without asking: you have to inventory with ss everything the node has listening, justify in writing every port that does belong there, and close the one that does not without bringing the control plane down; grading demands the port closed, the unit that opened it disabled so it cannot come back on its own, and the kubelet plus the seven control plane ports still healthy, so switching services off wholesale to make ss go quiet is also a fail.

## Prerequisites

- A Linux machine with kind, kubectl and docker on PATH, internet access, and at least 4 GB of free RAM. This lab creates its own kind cluster named cks-p03, with a single node, and deletes it at the end. Everything it does goes through a private kubeconfig at ~/cks-lab/p03/kubeconfig, passed with --kubeconfig on every command: your usual kubeconfig is never touched, your current context never changes, and no other cluster of yours is affected. Do not run this lab against a production cluster.
- Versions this lab was run with on 2026-10-11: kind v0.33.0, kubectl client v1.37.0, Docker 29.9.0, node running Kubernetes v1.36.1, node image kindest/node:v1.36.1 pinned by digest sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, and the workload image busybox:1.37.0 pinned by digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Confirm your kind with kind version and your kubectl with kubectl version --client before you start, rather than taking this paragraph's word for it.
- Your kernel must have AppArmor enabled. A kind node is not a virtual machine: it is a container sharing your computer's kernel, so seccomp and AppArmor come from the host kernel, not from the cluster. Check it yourself with cat /sys/module/apparmor/parameters/enabled, which on the machine where this lab was executed returns Y. If it returns N, or the file does not exist, the setup stops with the error SUSTRATO_SIN_APPARMOR_EN_EL_HOST and tells you what is missing: Steps 1, 2 and 4 would still work, but Step 3 would be grading a control nobody enforces, and that is decoration.
- Read this before running the setup, because it touches your machine and not only the cluster. Making AppArmor work inside a kind node needs three things the node image does not ship: mounting securityfs at /sys/kernel/security inside the node, dropping the apparmor_parser binary in there, and restarting containerd, because containerd decides once at startup whether the host supports AppArmor and keeps that answer. The setup does all three. The consequence you need to know about: a profile loaded that way does not live inside the cluster, it lives in your kernel's root AppArmor namespace, and it survives kind delete cluster. That is why every profile in this lab starts with cks-p03- and why the teardown unloads them from the kernel before deleting the cluster. If you abort the lab abruptly, unload them by hand with the command the teardown uses.
- The setup does not just build the cluster: it runs three substrate tests on it before letting you start, because all four steps assume behaviors a cluster can accept over the API and never actually enforce. It checks that seccomp RuntimeDefault blocks a system call that goes through without it, that a Localhost profile placed on the node's disk does reach the container, and that an AppArmor profile ends up in enforce over the process. If any of them fails, the setup prints a named error and stops.
- Having read Chapters 5 and 6. This lab does not re-explain what a system call is, what the difference between seccomp and a capability is, or why one extra open port is one extra open door; it makes you operate all four against a real cluster and grades them against its real state.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 6: The guard's regulation uniform, and the twin who stayed in street clothes (10 pts)

Chapter 6 told you the guard's uniform is not decoration: it is the list of things he may do inside the complex, and anything not on that list simply cannot be done. Seccomp is the same idea, except the list is of system calls and the one checking it is the kernel, not the gatehouse.

It is easy to write `seccompProfile: RuntimeDefault` into the manifest, watch the Pod go Running and call the job done. That is the problem: a field accepted by the API server is not a filter loaded in the kernel. The only proof that counts is asking the live process, and the live process tells you in `/proc/1/status`, on the `Seccomp:` line, which reads 0 for nothing, 1 for strict mode and 2 when a filter is in place.

One detail is easy to overlook. A system call failing inside a container does not prove seccomp blocked it. In an ordinary container plenty of calls fail for a completely different reason: they want a capability the container does not hold. If you test with one of those, you get an Operation not permitted that demonstrates nothing, because it would have failed just the same without seccomp. That is why this step leaves a twin beside you: same container, same image, same capabilities, no uniform. The proof is not that your Pod fails. The proof is that the twin succeeds and yours does not.

A costly mistake in this step is taking the uniform off the twin so "both come out the same", or deleting it because it is in the way, or letting it fall over without noticing. That Pod you did not create is the step's measuring instrument. Without it all you have left is a container that fails, and a container that fails is not a secured container; it may simply be a broken one.

DELIVERABLE: the `celaduria-con-uniforme` Pod running in the `conjunto` namespace, with the runtime's default seccomp profile declared, the twin `celaduria-sin-uniforme` untouched, as the setup left it, and the file `~/cks-lab/p03/01-respuesta.txt`, exactly 3 lines:

```text
MODO_SECCOMP_CON_UNIFORME=<the number on the Seccomp: line of /proc/1/status inside your Pod>
MODO_SECCOMP_SIN_UNIFORME=<the same number, measured inside the twin>
LLAMADA_BLOQUEADA=<the hexadecimal flag the error message names when your Pod tries to create a user namespace, written as it prints it>
```

<details>
<summary>What you should see</summary>

The first query prints gemelo=Unconfined, which is what the setup left on the guard with no uniform. The new Pod starts without trouble and both greps over /proc/1/status return Seccomp: 2 for the one wearing the uniform and Seccomp: 0 for the twin; 2 is SECCOMP_MODE_FILTER and 0 is SECCOMP_MODE_DISABLED, per proc(5). There is the first proof, and it does not come from the manifest but from the kernel. The unshare -U on the twin prints nothing and returns gemelo_unshare_rc=0, meaning creating a user namespace is possible with no seccomp and no added capability. The same command on the uniformed guard prints unshare: unshare(0x10000000): Operation not permitted and returns uniforme_unshare_rc=1. That 0x10000000 is CLONE_NEWUSER, and the only difference between the two Pods is the seccomp profile: same image, same capabilities, same node. The last two lines are the step's negative control: unshare -m fails on both, with unshare: unshare(0x20000): Operation not permitted, because 0x20000 is CLONE_NEWNS and that one wants CAP_SYS_ADMIN, which neither of them has. Failing does not prove seccomp acted; what proves it is that one fails and the other does not.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 6: A padlock cut to the shape of the shop, kept on the node's own disk (10 pts)

The runtime's profile is designed for generic workloads, and that is its limit: it is a hardware-store padlock, cut for an average door. Chapter 6 talked about the limited uniform; this step is the tailor. A Localhost profile is a profile you write, that you store on the node's disk, and that the kubelet hands to the runtime by name.

Here's what's actually going on: "on the node's disk" is literal. `localhostProfile` is not a path on your filesystem nor a ConfigMap: it is a path relative to the kubelet's profile root, which on Linux is `/var/lib/kubelet/seccomp`. The file has to be on every node the Pod might land on, placed there before the Pod starts, and if it is not, the container does not wait around: it fails with CreateContainerError. In this lab the node is a docker container, so you go in with `docker exec`; on a real cluster you would go in over SSH, or drop the file with a DaemonSet, or use the Security Profiles Operator.

The other half of the craft is choosing the default action. A profile with `defaultAction` at `SCMP_ACT_ERRNO` denies everything not on the list, and it sounds strict until you realize a modern container makes hundreds of distinct calls just to start, and that the first one missing kills the process before it prints anything. That is why this exercise starts from the other end: allow by default and deny one specific family. It is less elegant and it is much more honest as a first profile.

A tempting shortcut is to leave the profile in place while the Pod starts and delete the file afterwards, because "it is applied already". It is true that it is applied, the filter lives in the kernel and the Pod stays confined. It is also true that the day that Pod restarts, or the node is replaced, or the ReplicaSet makes another one, the padlock no longer exists and nobody is going to find out. That is why grading walks into the node to see whether the file is still there.

DELIVERABLE: the profile file `/var/lib/kubelet/seccomp/profiles/candado-del-local.json` on the node `cks-p03-control-plane`, a profile that lets the container work but denies it the `chmod` call family; the `tienda-del-conjunto` Pod in the `conjunto` namespace using it through `localhostProfile`; and the file `~/cks-lab/p03/02-respuesta.txt`, exactly 2 lines:

```text
RUTA_DEL_PERFIL=<the localhostProfile value your Pod declares, read from the cluster>
ACCION_POR_DEFECTO=<the defaultAction value the profile file on the node carries>
```

<details>
<summary>What you should see</summary>

The cat over the node's file gives you back the JSON as you wrote it, with defaultAction at SCMP_ACT_ALLOW and a single syscalls entry putting SCMP_ACT_ERRNO on the chmod family. The Pod starts without trouble, because a profile that allows by default takes nothing away from the container that it needs to live. The grep returns Seccomp: 2, the same as in Step 1: to the kernel there is no difference between the runtime's profile and yours, both are a loaded BPF filter. The touch works and returns touch_rc=0. The chmod prints chmod: /tmp/inventario: Operation not permitted and returns chmod_rc=1, which is the errnoRet 1 (EPERM) you asked for in the profile. And the last query prints ruta=profiles/candado-del-local.json: notice it is a relative path, with no leading slash, because localhostProfile is resolved against the kubelet's profile root, which on Linux is /var/lib/kubelet/seccomp. If you write the absolute path there, the kubelet does not find the file and the container sits in CreateContainerError.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 6: The storeroom where you may look at everything and write nothing (10 pts)

Seccomp decides which system calls a process may make. AppArmor decides what it may make them on: which files, which paths, which capabilities, which network. They are different layers and they add up, and Chapter 6 treated them together for that reason: the uniform says what the guard may do, and the profile says in which part of the complex.

AppArmor in Kubernetes has a rule worth knowing up front: the cluster does not distribute profiles. There is no AppArmorProfile object, no ConfigMap that syncs itself. The profile has to be loaded in the kernel of every node the Pod might land on, before the Pod starts, and you put it there from outside Kubernetes: with `apparmor_parser`, over SSH, with a DaemonSet, or with the Security Profiles Operator. Kubernetes' `appArmorProfile` field only names a profile that already exists.

And the word that costs money on exam day is `enforce`. AppArmor loads profiles in two modes: enforce, which denies for real, and complain, which denies nothing and only writes to the audit log what it would have denied. Complain exists so you can develop profiles without breaking anything, and it is an excellent tool. It is also the quietest way to believe a system is secured when it is not. A profile in complain looks identical in the manifest, looks identical in `kubectl describe`, and only gives itself away when you read the mode it ended up in.

A shortcut that looks elegant: when the Pod will not start because of the profile, switch the type to `Unconfined` to "get past it" and carry on with the lab. The Pod starts in three seconds, the YAML still has its appArmorProfile section, and everything looks fine. The only thing that changed is that there is no longer a profile. That is why grading does not read the manifest: it asks the container's process number 1 which profile it is running under, and that cannot be typed by hand.

DELIVERABLE: an AppArmor profile named `cks-p03-bodega-sin-lapicero`, loaded in enforce mode on the node `cks-p03-control-plane`, denying every write and allowing reads; the `bodega` Pod in the `conjunto` namespace running under that profile through the `appArmorProfile` field; and the file `~/cks-lab/p03/03-respuesta.txt`, exactly 2 lines:

```text
PERFIL_DEL_PROCESO=<what cat /proc/1/attr/current returns inside the bodega Pod, verbatim, parentheses included>
MODO_EN_EL_NODO=<the word in parentheses beside your profile in the node's list of loaded profiles>
```

<details>
<summary>What you should see</summary>

apparmor_parser prints nothing when it succeeds, which is normal for AppArmor tooling, and the next grep confirms the load with the line cks-p03-bodega-sin-lapicero (enforce). That word in parentheses is half the step: enforce means it denies, complain means it only writes to the log and lets things through. The Pod starts and goes Ready. The cat of /proc/1/attr/current prints cks-p03-bodega-sin-lapicero (enforce), which is the profile as seen from inside the container, by the process itself. The cat of /etc/hostname prints bodega and returns lectura_rc=0, because the profile says file, which grants file access, and only then denies writes. The touch prints `touch: /tmp/remision: Permission denied` and returns escritura_rc=1. Notice the change of vocabulary from Step 1: seccomp returns Operation not permitted because the filter answers EPERM to the call, and AppArmor returns Permission denied because the LSM refuses access to the file. They are two different kernel layers saying no for two different reasons.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 5: The yard with a back exit nobody authorized (10 pts)

Chapter 5 talked about the empty room: every room nobody uses, every door nobody watches, every service installed "just in case" is surface somebody can touch. And Chapter 6 talked about the yard with no back exit. This step brings them together on the node itself, which is the machine holding the cluster up and has an attack surface of its own.

A Kubernetes node has two classes of port and confusing them is expensive. Those listening on 127.0.0.1 are reachable only from inside the machine: the kubelet's healthz, kube-proxy's metrics, the controller-manager, the scheduler, etcd for its own plane. And those listening on the node's IP or on the wildcard are reachable from the network: the API server on 6443, the kubelet on 10250, kube-proxy's healthz on 10256, etcd on 2379 and 2380 between members. That second list is the node's real attack surface, and it is a short list you should be able to recite.

The work here is not memorizing ports, it is learning to ask the machine and to justify what you find. `ss -lntp` tells you what is listening and which process opened it. But when the process is systemd with pid 1, ss cannot tell you any more, and that is where you change tools: `systemctl list-sockets` gives you the unit's name, and with the name you can read the file, understand what it activates and decide.

The costly mistake here is closing by brute force. When you see a list of ports you do not understand, the temptation is to switch services off until the list gets short. That is where somebody stops the kubelet "because 10250 looks dangerous" and takes the whole node down with it, or kills etcd and takes the cluster. Hardening is not switching off: it is knowing which port belongs to whom, why it has to be there, and removing only the one with no owner. And closing is not stopping either: a socket unit stopped but still enabled comes back on its own at the next boot, and you are left thinking you closed something.

DELIVERABLE: the node `cks-p03-control-plane` with no outward-facing TCP port listening that is not Kubernetes', with no socket units enabled, with a healthy kubelet and the node Ready; and the file `~/cks-lab/p03/04-respuesta.txt` with one line for each of the seven control plane ports (2379, 2380, 6443, 10250, 10256, 10257, 10259), in this exact format, with vertical bars and no spaces around them:

<port>|<process name exactly as ss reports it>|<your justification, at least 25 characters>

For example, one line of the file looks like this: `6443|kube-apiserver|It is the only entrance to the cluster API and kubectl and every node use it.`

<details>
<summary>What you should see</summary>

The first ss shows you the node's complete inventory, and it is worth reading slowly because not all ports are alike. On 127.0.0.1 you find the kubelet's healthz on 10248, kube-proxy's metrics on 10249, kube-controller-manager on 10257, kube-scheduler on 10259, etcd on 2379 and its metrics on 2381, plus a high, variable containerd port; on 127.0.0.11 sits docker's internal DNS, also on a variable port. All of that is reachable only from the node itself. The second output leaves only what listens on addresses reachable from outside, and on a clean node there are five: the node's IP on 2379 and 2380 for etcd, and the wildcard on 6443 for kube-apiserver, 10250 for the kubelet and 10256 for kube-proxy's healthz. On the machine where this lab was executed on 2026-10-11 a sixth appears, on 34521, which does not belong on that list. The systemctl list-sockets tells you who opened it, with unit and service names, which is information ss cannot give you because ss can only tell you the process is systemd with pid 1. After the disable the second ss no longer shows it, is-active returns active and the healthz returns kubelet_healthz=200, and the node stays Ready.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

## How to run it

```bash
./00-setup.sh                  # creates the cluster and sets everything up
./01-step.sh && ./01-check.sh  # do the step, check it landed
./02-step.sh && ./02-check.sh
./03-step.sh && ./03-check.sh
./04-step.sh && ./04-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

## Troubleshooting

- **Symptom (step 1):** The call I picked to test fails in both Pods, with and without the uniform
  **What to do:** You picked a system call that wants a capability, not one seccomp filters on its own. Containerd's default profile has a whole group of calls allowed only if the container holds CAP_SYS_ADMIN (mount, setns, unshare, syslog, bpf, perf_event_open and several more), and those same calls also fail without seccomp because the kernel wants the capability. The clean case is different: unshare with CLONE_NEWUSER needs no capability at all on a kernel that allows unprivileged user namespaces, so it goes through without seccomp and does not with RuntimeDefault. If on your machine it fails in the twin too, your kernel is restricting user namespaces by another route; check with sysctl kernel.apparmor_restrict_unprivileged_userns and sysctl kernel.unprivileged_userns_clone.

- **Symptom (step 1):** I declared RuntimeDefault and /proc/1/status still says Seccomp: 0
  **What to do:** Check where you put the field. seccompProfile lives under securityContext, and the Pod's securityContext is at spec.securityContext while the container's is at spec.containers[N].securityContext; if you wrote it loose under spec, or under the container but outside securityContext, the API server may accept the manifest and apply nothing. Read it back from the cluster, not from the file, with kubectl --kubeconfig ~/cks-lab/p03/kubeconfig -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.spec.securityContext.seccompProfile}{.spec.containers[0].securityContext.seccompProfile}'. And remember the field cannot be changed on an existing Pod: you have to delete it and create it again.

- **Symptom (step 2):** The Pod sits in CreateContainerError and the event says it cannot find the profile
  **What to do:** It is usually a path problem. localhostProfile resolves against the kubelet's profile root, /var/lib/kubelet/seccomp on Linux, so the correct value is relative and without a leading slash: profiles/candado-del-local.json, not /var/lib/kubelet/seccomp/profiles/candado-del-local.json. Confirm the file exists where the kubelet will look with docker exec cks-p03-control-plane ls -l /var/lib/kubelet/seccomp/profiles/ and read the full event with kubectl --kubeconfig ~/cks-lab/p03/kubeconfig -n conjunto describe pod tienda-del-conjunto. Another possible cause is malformed JSON: the runtime cannot parse it and the error looks similar.

- **Symptom (step 2):** The container starts and dies immediately, with no useful log
  **What to do:** You probably put defaultAction at SCMP_ACT_ERRNO without a sufficient allow-list, and the process died before it could write anything. To diagnose it without guessing, temporarily change defaultAction to SCMP_ACT_LOG, which lets everything through but records every call, recreate the Pod and read the kernel's audit messages; with that list you can then build a deny-by-default profile that works. For this step, though, you do not need to: the deliverable asks for a profile that allows by default and denies one family, which is the short road and the verifiable one.

- **Symptom (step 3):** The Pod sits in AppArmor status and the event says Cannot enforce AppArmor: AppArmor is not enabled on the host
  **What to do:** That message comes from the kubelet, and the kubelet decides whether AppArmor is available by looking at three things: that /sys/module/apparmor/parameters/enabled says Y, that the directory /sys/kernel/security/apparmor exists, and that apparmor_parser is on the node's PATH. The setup mounts securityfs and drops the parser, but the kubelet makes that decision at startup, so if you touched it afterwards it needs a restart: docker exec cks-p03-control-plane systemctl restart kubelet. Check the three conditions by hand with docker exec cks-p03-control-plane sh -c 'cat /sys/module/apparmor/parameters/enabled; ls /sys/kernel/security/apparmor; command -v apparmor_parser'.

- **Symptom (step 3):** The Pod sits in CreateContainerError and the message says apparmor is not supported, or apparmor profile not found
  **What to do:** Those are two different causes with different fixes. If it says apparmor is not supported, the one not convinced is containerd, not the kubelet: containerd runs that check once at startup and keeps the answer, so if securityfs was mounted afterwards it needs a restart with docker exec cks-p03-control-plane systemctl restart containerd and a wait for the node to go Ready again. If it says apparmor profile not found followed by a name, the profile is simply not loaded on that node: check the exact name, which is the one inside the profile file after the word profile and not the file's name, and confirm it with docker exec cks-p03-control-plane grep cks-p03 /sys/kernel/security/apparmor/profiles.

- **Symptom (step 3):** I unloaded the profile from the kernel to fix it, loaded it back in enforce, and now the Pod says unconfined
  **What to do:** That is the correct behavior and it is worth seeing once. The profile is attached to the process when the container starts; if you unload it from the kernel while the Pod is alive, the process is left with no label and /proc/1/attr/current starts saying unconfined, and loading the profile back under the same name does not give it back, because nothing relabels a process that is already running. The confusing part is that in that situation some writes may still fail for other reasons, so a touch's output will not tell you whether things are right. The practical rule: every time you touch the profile on the node, delete the Pod and create it again, and always confirm by reading /proc/1/attr/current, which is what grading does.

- **Symptom (step 4):** ss tells me the port was opened by systemd with pid 1 and the trail ends there
  **What to do:** It did not end, it changed tools. When systemd holds the socket, it is because a .socket unit opened it, usually to activate a service on demand. Ask systemd directly with docker exec cks-p03-control-plane systemctl list-sockets, which gives you three columns: the listening address, the socket unit and the service it activates. With the unit's name you can read it whole with systemctl cat <unit> and see the ListenStream and the ExecStart of what it activates. To close it for real you have to disable it, not only stop it, because enabled means it comes back on its own at the next boot.

- **Symptom (step 4):** I closed the extra port and the check still fails
  **What to do:** Check the four demands separately, because the check asks for more than the port being closed. First, that no socket unit is left in state enabled: look at it with docker exec cks-p03-control-plane systemctl list-unit-files --type=socket and look for the word enabled in the second column. Second, that the seven control plane ports are still listening: if you stopped a service along the way, bring it back up. Third, that the kubelet is still active and its healthz on 127.0.0.1:10248 returns 200. Fourth, the file's format: lines carry no spaces around the bars, the process name has to be the one ss reports at that moment, which comes truncated to 15 characters by the kernel (which is why kube-controller-manager shows up as kube-controller), and the justification has to be at least 25 characters long.

## Going further

- Go back to Step 2 and change the shop profile's defaultAction to SCMP_ACT_LOG, without touching the syscalls list, and recreate the Pod. Now nothing gets blocked, but the kernel writes every call the process makes into its audit log. Read it from the node with docker exec cks-p03-control-plane sh -c 'dmesg | grep -i seccomp' and observe how many distinct calls a busybox that only sleeps actually needs. That is the real method for building a deny-by-default profile: first you measure, then you write the list.
- Load the storeroom profile in complain mode with apparmor_parser -C instead of -r, recreate the Pod and repeat Step 3's two tests. You will see the profile name still shows up in /proc/1/attr/current, the manifest looks identical, and the touch now works. Then read what the kernel logged about that write. That exercise shows you, on your own machine, why Step 3's grading reads the mode and not only the name.
- Put the Pod Security Admission labels on the conjunto namespace in warn mode with pod-security.kubernetes.io/warn=restricted and recreate the lab's four Pods exactly as you have them. Read the API server's warnings carefully: the restricted profile requires seccompProfile RuntimeDefault or Localhost, so the guard with no uniform will draw a warning and yours will not. It is a way of seeing Step 1's same rule enforced by admission instead of by manual review.
- Repeat Step 4's inventory against a node that is a real machine and not a container: any Linux VM will do. Compare the two ss listings and notice everything that appears on the VM and not on the kind node (sshd, the DHCP client, the local resolver, sometimes a mail server nobody asked for). That difference is what Chapter 5 meant when it said the empty room is surface too.

## References

- Kubernetes Project, Restrict a Container's Syscalls with seccomp. Primary source for the seccompProfile field, for the RuntimeDefault, Localhost and Unconfined types, and for the example profiles whose defaultAction values (SCMP_ACT_ALLOW, SCMP_ACT_ERRNO, SCMP_ACT_LOG) Steps 1 and 2 build on. https://kubernetes.io/docs/tutorials/security/seccomp/
- Kubernetes Project, Seccomp reference (node reference). Primary source for the statement that a Localhost profile has to be available on the node disk at /var/lib/kubelet/seccomp on Linux, that localhostProfile is relative to that root, and that a missing profile fails container creation with CreateContainerError. Both facts are graded in Step 2. https://kubernetes.io/docs/reference/node/seccomp/
- Kubernetes Project, Restrict a Container's Access to Resources with AppArmor. Primary source for securityContext.appArmorProfile with its type and localhostProfile fields, stable since v1.31 and replacing the pre-v1.30 annotation, for the deny-write example profile Step 3 mirrors, for loading profiles onto nodes with apparmor_parser, and for the prerequisite checks on /sys/module/apparmor/parameters/enabled and /sys/kernel/security/apparmor/profiles. https://kubernetes.io/docs/tutorials/security/apparmor/
- Open Container Initiative, Runtime Specification, Linux configuration. Defines the seccomp object a Localhost profile file must match: defaultAction, architectures, syscalls with names and action, and the full set of action constants including SCMP_ACT_ERRNO, SCMP_ACT_ALLOW and SCMP_ACT_LOG. https://github.com/opencontainers/runtime-spec/blob/main/config-linux.md
- containerd Project, contrib/seccomp/seccomp_default.go. The profile Kubernetes RuntimeDefault actually resolves to on a containerd node: defaultAction ActErrno, a base allow-list, and a group of syscalls (mount, setns, unshare, syslog, bpf, perf_event_open and others) added only when the container holds CAP_SYS_ADMIN. It is the reason Step 1's discriminator has to be a call that needs no capability. https://github.com/containerd/containerd/blob/main/contrib/seccomp/seccomp_default.go
- Linux man-pages Project, proc_pid_status(5). Documents the Seccomp field of /proc/PID/status, with 0 for SECCOMP_MODE_DISABLED, 1 for SECCOMP_MODE_STRICT and 2 for SECCOMP_MODE_FILTER, which is the live measurement Steps 1 and 2 grade instead of trusting the manifest. https://man7.org/linux/man-pages/man5/proc_pid_status.5.html
- Linux man-pages Project, seccomp(2). Primary source for seccomp filter modes and for the fact that a filter is inherited and cannot be removed once installed, which is why deleting a Localhost profile file leaves a running Pod confined while leaving nothing behind for the next one. https://man7.org/linux/man-pages/man2/seccomp.2.html
- Linux man-pages Project, user_namespaces(7). Documents that creating a user namespace with unshare or clone requires no capability in the caller's namespace on a kernel that allows unprivileged user namespaces, which is exactly what makes it a clean discriminator between an Unconfined container and a RuntimeDefault one in Step 1. https://man7.org/linux/man-pages/man7/user_namespaces.7.html
- AppArmor Project, apparmor_parser(8) and the AppArmor core policy reference. Primary source for loading and replacing profiles with -r, for loading in complain mode with -C, and for the enforce and complain modes that Step 3 reads out of /sys/kernel/security/apparmor/profiles. https://gitlab.com/apparmor/apparmor/-/wikis/Documentation
- Kubernetes Project, Ports and Protocols. Primary source for the control plane and worker node port inventory Step 4 grades: 6443 for the API server, 2379 and 2380 for etcd, 10250 for the kubelet, 10256 for kube-proxy, 10257 for kube-controller-manager and 10259 for kube-scheduler. https://kubernetes.io/docs/reference/networking/ports-and-protocols/
- systemd Project, systemd.socket(5) and systemctl(1). Primary source for socket units with ListenStream, for socket activation, and for the difference between stopping a unit and disabling it, which is the distinction Step 4's check enforces when it refuses any socket unit left in state enabled. https://www.freedesktop.org/software/systemd/man/latest/systemd.socket.html
- kubernetes-sigs/kind, release v0.32.0. Publishes the pre-built node images for this kind release, including the kindest/node:v1.36.1 digest the setup script pins, and documents the --config and --kubeconfig flags this lab uses to build its own cluster without touching any other kubeconfig. https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
