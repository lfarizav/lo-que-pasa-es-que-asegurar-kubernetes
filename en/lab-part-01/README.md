# Part I - Lab: tower three's visiting rules, the watchman's inspection before his shift, the entrance that does ask for ID, and the new guard whose badge gets checked before he is let in

- Time: 45-60 min
- Points: 40

## Objective

This is an Exam-Style lab: each step states only the objective, and that step's exact command sequence lives in its cmd field for you to reveal after you have tried on your own first. Step 1 puts Chapter 1's default-deny posture in place, and in security that covers both directions: you deny what comes in and what goes out, and only then open a single door with a name on it, including the egress to cluster DNS without which the authorized neighbour cannot even resolve the intercom's name. Step 2 has you run Aqua Security's kube-bench against your own kind cluster's control plane, read the CIS benchmark report, pick one of the failed controls that can be fixed in kind, fix it by editing the static pod manifest, and end with the cluster still Ready: the check re-runs kube-bench from a digest-pinned image, so there is no way to silence the control by editing the tool's configuration. Step 3 has you build Chapter 2's entrance with verified ID: a self-signed certificate, a kubernetes.io/tls Secret, an Ingress with a tls block, and the test that goes beyond a 200 status, which is comparing the SHA-256 fingerprint of the certificate the controller is serving with the one you stored. Step 4 closes on the binary: you read the cluster's minor version from the API itself, download kubectl from that line together with its official .sha256 from dl.k8s.io, confirm they agree, and then corrupt a single byte of a copy to watch the check fail. No check reads your history: every one of them re-queries the cluster, and several of them generate fresh traffic or ask the project again at grading time.

## Prerequisites

- A Linux machine with kind, kubectl, docker, curl, openssl, base64, sha256sum, dd and ss on the `PATH`, and at least 4 GB of free RAM. The lab creates its own kind cluster named cks-p01 and writes its kubeconfig to a private file, ~/cks-lab/p01/kubeconfig, which is not your usual one. Every command passes --kubeconfig pointing at that file, so your ~/.kube/config is never modified and no other cluster of yours is touched. The teardown deletes only the cks-p01 cluster and the ~/cks-lab/p01 folder.
- Host ports 8091 and 8449 free. The cluster is created with extraPortMappings taking host 8091 to the node's port 80 and 8449 to 443, which is how you ring the entrance's bell in Step 3. Those numbers were chosen deliberately instead of the usual 8080 and 8443, because those two may already be taken by another service on your machine. Confirm with ss -ltn before you start; if either is busy, change the number in kind-p01.yaml and in the Step 3 commands.
- Internet access when you set the lab up and when you grade it. The setup downloads the Calico, Ingress controller and kube-bench manifests plus container images from quay.io, registry.k8s.io and docker.io. Step 4's check asks dl.k8s.io again for the binary's official sum, because that is the only honest way to grade an integrity verification: if the grader takes the sum file on faith without asking the project again, you could write whatever sum you liked. If that lookup fails, the check prints the named error `ERROR SIN-INTERNET-PARA-CALIFICAR` and exits non-zero, instead of handing you a pass that means nothing.
- Node image pinned by digest, read out of the kind v0.32.0 binary on 2026-08-21 and used unchanged in the full run of the lab on 2026-10-11, made with kind v0.33.0, kubectl client v1.37.0 and Docker 29.9.0: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5. The kind release notes say you must use the @sha256 digest to guarantee an image built for that release, not just the tag. Confirm yours with kind version and docker images --digests, never from memory. The server version that image carries is v1.36.1, and Step 4 reads it live from the API, so if you use a different image the lab adapts on its own.
- Pinned CNI: Calico v3.32.1, published 2026-06-26 and verified against the project's releases on 2026-08-21. This piece is not decoration. The cluster is created with disableDefaultCNI set to true precisely because the CNI kind ships by default does not enforce NetworkPolicy, and without a CNI that enforces it the whole of Step 1 would be theatre. There is one detail that costs dearly: the custom-resources.yaml that Calico publishes defaults to an IP pool of 192.168.0.0/16, a range that can collide with your LAN's. That is why this lab does not use that file: it writes its own Installation resource with cidr 10.244.0.0/16, the same podSubnet declared to kind. The CRDs go in first and explicitly, because the operator also installs them by itself, but a few seconds after it becomes available, and applying the Installation straight away fails with no matches for kind Installation.
- The setup measures the substrate, it does not assume it. Before handing you the lab, the setup brings up a throwaway probe namespace, confirms one Pod talks to another with no policy in place, applies a total deny, and tests again. If traffic still passes, the setup prints the named error `ERROR SUSTRATO-SIN-NETWORKPOLICY` and exits non-zero, because on that cluster Step 1 would prove nothing. It is the only honest way to build a NetworkPolicy lab: an object can be accepted by the API and enforced by nobody. Measured on the reference machine on 2026-08-21: baseline exit 0, with a total deny exit 1.
- Pinned kube-bench: docker.io/aquasec/kube-bench:v0.16.0@sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679, published 2026-08-05, multi-platform index digest read with docker buildx imagetools inspect on 2026-08-21. Running against this cluster, kube-bench detects version 1.36 and picks the cis-1.12 benchmark on its own; you do not have to pass --benchmark. On the freshly built cluster the report shows 10 controls in FAIL, and that number is deterministic for this node image and this tool version. Step 2 asks you for it.
- Pinned Ingress controller, with a caveat that has to be stated in full: ingress-nginx controller-v1.15.1, published 2026-03-19, is the last version that will ever exist. The kubernetes/ingress-nginx project was retired and its repository is archived read-only; there will be no more bug fixes and no more security patches, ever. Verified on 2026-08-21 against the GitHub API, which reports archived true for that repository and lists no later release. The manifest still downloads because an archived repository is not deleted, and the lab uses it deliberately, with an explicit pin, because the CKS curriculum still asks you to secure an Ingress with TLS and because knowing that the company which maintained the entrance shut down is the kind of thing a security engineer has to say out loud before somebody proposes it in production.
- Application images pinned by digest, verified on 2026-08-21 with docker buildx imagetools inspect: nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de for the apartment and the intercom, and busybox:1.37@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 for the client Pods, which is the image carrying a wget with a bounded timeout. A tag is mutable, a digest is not.
- Having read Chapters 1 and 2. This lab does not re-explain why a cluster with no NetworkPolicy lets any tower talk to any other, what the CIS benchmark checks, why an entrance with no TLS lets in anyone who says the right name, or why an unverified binary is a guard with no ID of his own; it makes you operate all four against a real cluster. One warning up front: the kind node has no vi and no nano, only sed. Measured on 2026-08-21. If you were planning to go into the node and hand-edit a static pod manifest, that fact saves you a good deal of frustration.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 1: Tower three's visiting rules, denying what comes in and what goes out (10 pts)

Chapter 1 left the housing complex fully drawn: with no visiting rules, anybody who walks through the entrance can go up any tower, knock on any door and stay for a chat. In Kubernetes that is not a loose metaphor, it is the networking model written in the official documentation: all Pods talk to all Pods with no address translation in between, and that is your cluster's factory state.

The setup already left three neighbours living in tower three. Apartment 301 serves a page on port 80 and has its own intercom, a ClusterIP Service called citofono-301. The authorized neighbour carries the label visita=autorizada. The stranger at the gate carries visita=negada. You do not have to create any of the three: what you write is the rulebook.

And here is the difference between this lab and a development one. In security, default deny does not stop at the entrance. A policy denying only what comes in leaves the back door wide open: a compromised Pod does not need anybody to reach it, it needs to be able to get out, and with egress left open it goes wherever it likes, inside and outside the cluster. Your default deny carries both: Ingress and Egress, with an empty podSelector, with no rule inside. Remember what the chapter said: an empty podSelector does not select zero Pods, it selects every Pod in the namespace.

Then open a single door, with a name on it, and here comes the detail that fails the exam: it is not enough to let the neighbour into the apartment. If you closed everybody's egress and open only the egress towards the apartment on port 80, the neighbour can arrive by IP and cannot arrive by name, because resolving the name means talking to cluster DNS, and DNS lives in another namespace and listens on port 53. That is an easy production mistake with NetworkPolicy: closing egress and forgetting about 53.

And do it in the right order: measure first. Before applying anything, run both wgets and see with your own eyes that both exit 0. That baseline is not paperwork, it is the only way to know afterwards that what changed was the rulebook and not something else. The setup already measured that this cluster enforces NetworkPolicy, but your namespace's baseline is yours to measure.

One last warning: if it occurs to you to hand the stranger an authorized-visitor badge so the symptom disappears, traffic will flow and the step will fail. The check hint says so outright.

DELIVERABLE: the network policies you write in la-torre-tres, with the three Pods intact and carrying their original labels, and the file `~/cks-lab/p01/01-respuesta.txt`, exactly 3 lines:

```text
SALIDA_VECINO=<the exit code of the authorized neighbour's wget against the Service's fully qualified name, after applying the rulebook>
SALIDA_DESCONOCIDO=<the exit code of the stranger's wget against the apartment's IP, after applying the rulebook>
POLITICAS_EN_LA_TORRE=<how many NetworkPolicy objects ended up alive in the la-torre-tres namespace>
```

<details>
<summary>What you should see</summary>

In the baseline both wgets return exit code 0: the tower is wide open and any Pod talks to any other, as the Kubernetes networking model says. kubectl get networkpolicies lists all three policies, and the default-deny one shows `POD-SELECTOR` as `<none>`, which is how kubectl displays the empty selector that selects everything. After applying all three, the authorized neighbour's wget against the Service's fully qualified name still returns 0, and the stranger's goes silent for the full eight seconds and returns 1, which is what a timeout looks like rather than a refusal: nobody tells it no, nobody answers it at all. If the neighbour by name returns 1 but by IP returns 0, do not panic: that means egress to TCP 80 is open and egress to DNS is not, and it is an easy mistake to make in this part.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 1: The watchman's inspection before his shift, and fixing one of the things that came out wrong (10 pts)

Chapter 1 ended on the inspection before the shift: the watchman coming on duty does not improvise, he takes out the list and ticks it off. In Kubernetes that list is called the CIS benchmark, and the tool that walks it for you is kube-bench, from Aqua Security. The setup already wrote you the Job manifest, with the image pinned by digest, at `~/cks-lab/p01/kube-bench-job.yaml`.

Run the inspection and read the whole report, not just the summary. Notice two things that are easy to skip. The first: right at the top, kube-bench says which version it detected and which benchmark it picked by itself, and on this cluster it picks cis-1.12 on its own, without you passing --benchmark. The second: there are more WARN lines than FAIL, and a WARN in CIS is not an error, it is a manual control the tool cannot decide for you.

Now pick one, not the ten. Just one, from the four that in kind are fixed with a single flag, listed by number in the check hint. And here is a measured fact about the machine that will save you some frustration: the kind node has no vi and no nano. Only sed. The static pod manifest lives inside the node container, in /etc/kubernetes/manifests, so you go in with docker exec and edit with sed, or pull it out with docker cp, edit it outside, and put it back.

The lovely thing about static pods is what happens next: you restart nothing. The kubelet is watching that folder, sees a different file, and recreates the pod on its own. Wait for the live process to carry the new flag before grading again, because for a few seconds the old pod is still there.

Fixing a CIS control is not "making kube-bench stop complaining". That is what gets done when an audit presses: the tool's configuration is moved, or the component is switched off, and the report goes green with the complex just as open as before. That is why this step grades two things at once, the flag on the live process and the cluster still Ready. A control plane that is switched off fails no control, and is not secure for it.

DELIVERABLE: the control you picked, fixed in the manifest and visible in the live pod's command, the cluster Ready, and the file `~/cks-lab/p01/02-respuesta.txt`, exactly 3 lines:

```text
CONTROL_ARREGLADO=<the number of the control you fixed, for example 1.4.1>
FALLAS_ANTES=<how many checks FAIL the total summary of the first inspection reported>
FALLAS_DESPUES=<how many checks FAIL the total summary of the second inspection reports>
```

<details>
<summary>What you should see</summary>

The Job ends with condition=complete and its logs carry the whole report. At the very top kube-bench says it detected version 1.36 and picked the cis-1.12 benchmark without you passing --benchmark. The FAIL grep prints ten lines on the freshly built cluster: 1.1.12 on etcd's data directory ownership, 1.2.5 on --kubelet-certificate-authority, 1.2.15 on the API server's --profiling, 1.2.16 through 1.2.19 on the four audit log flags, 1.2.30 on --service-account-extend-token-expiration, 1.3.2 on the controller-manager's --profiling and 1.4.1 on the scheduler's --profiling. The total summary says 47 checks PASS, 10 checks FAIL, 50 checks WARN. After adding the flag to the scheduler, the static pod recreates itself in under a minute, kubectl get nodes still says Ready, and the second inspection prints the PASS line for 1.4.1 and a summary of 9 checks FAIL.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 2: The entrance with verified ID, and the fingerprint that proves whose ID it is (10 pts)

Chapter 2 said it with the entrance: the one that asks for nothing lets in anybody who says the right name, because anybody can say a name. The ID card is the thing you cannot say out loud, you have to show it, and whoever looks at it has to be able to confirm it belongs to who it claims.

The setup already installed the intercom in the la-porteria namespace: a Deployment serving a page on port 80 and its Service. That intercom answers plain HTTP and knows nothing about TLS, and it stays that way. What you build is the entrance, and the entrance is the one that shows the ID.

Three pieces, none of them spare. The first is the certificate, which you generate self-signed with openssl. Put the entrance's name in the CN, yes, but above all put it in the SAN, the Subject Alternative Name: today's clients stopped looking at the CN long ago, and a certificate with no SAN is an ID card with no photo. The second is the Secret, and it has to be of type kubernetes.io/tls, with the keys tls.crt and tls.key inside; an Opaque Secret holding the same files is no use to the controller. The third is the Ingress's tls block, which ties a host name to a Secret name, and is what makes kubectl get ingress's `PORTS` column go from saying 80 to saying 80, 443.

And now the part that separates a security engineer from somebody who watched a tutorial. When curl returns 200 and prints the content, you have still proved nothing. A 200 over HTTPS does not prove the ID is yours. It proves there was an ID. ingress-nginx, when it cannot find the Secret you named, does not crash and does not return an error: it pulls out a filler certificate it signed itself, named Kubernetes Ingress Controller Fake Certificate, and carries on serving as though nothing happened. The door looks shut and the ID is a fake.

That is why this step's last command opens a real TLS connection, sends the name over SNI, and takes the SHA-256 fingerprint of the certificate it was handed, to compare it with your own. That is what you do in production every single time somebody says the TLS is already in place.

DELIVERABLE: the kubernetes.io/tls Secret, the Ingress with its tls block pointing at the intercom, and the file `~/cks-lab/p01/03-respuesta.txt`, exactly 3 lines. Both fingerprints are written as openssl prints them after the equals sign, in upper case and with colons between each pair:

```text
HUELLA_DE_MI_CERTIFICADO=<the SHA-256 fingerprint of the certificate you generated>
HUELLA_SERVIDA_POR_LA_ENTRADA=<the SHA-256 fingerprint of the certificate the entrance handed you over the TLS connection>
CODIGO_HTTPS=<the HTTP code the https curl returned>
```

<details>
<summary>What you should see</summary>

openssl prints the certificate with subject CN equal to laporteria.local, the X509v3 Subject Alternative Name block carrying DNS:laporteria.local, and a sha256 Fingerprint line with thirty-two colon-separated digit pairs. The Secret ends up with type kubernetes.io/tls, which is the only way the controller will even look at it. The Ingress is listed with `CLASS` nginx, `HOSTS` laporteria.local and `PORTS` 80, 443: the ports column only says 443 when there is a tls block, and that is the at-a-glance sign the entrance got its ID. curl returns 200 and prints `LA PORTERIA CON CEDULA VERIFICADA`. And the last two fingerprints come out identical, digit for digit. If the second fingerprint differs and the subject says Kubernetes Ingress Controller Fake Certificate, the controller did not find your Secret and is handing every client its filler certificate: the door looks shut and the ID is a fake.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 2: The new guard gets his badge checked before he is let in (10 pts)

Chapter 2 closed on the new guard. One shows up at the entrance, says he is from the security company, and he is wearing the uniform. Do you let him in? The chapter's answer was that the uniform is not the identification, and that whoever checks has to be able to confirm it against the company, not against the man standing there.

On a platform that is what happens with binaries. You download kubectl, or kubeadm, or some component's binary, and you run it with high privileges against the production cluster. If the file came altered, it no longer matters how much RBAC you wrote: the one inside is the attacker and you let him in yourself.

This step is four moves and none of them is skippable.

The first: the version is not typed from memory. Ask the cluster which line it belongs to, with `kubectl get --raw /version`, and take the major and the minor from there. Then ask the project which is that line's latest stable, which is dl.k8s.io's stable file. Notice one detail: the line's latest stable may be several patches ahead of your server (v1.36.5 against v1.36.1 on 2026-10-11), and that is fine, because the project supports one minor version of skew between kubectl and the server.

The second: you download the binary and its sum, from the project's own site, not from the first link a search throws up.

The third: you verify before granting execute permission. That order is not fussiness. A binary with no chmod +x is just a file; with chmod +x it is a program you have just authorized. Verify first, authorize second.

The fourth is the one that teaches, and that is why this lab forces it: make a copy and change a single byte in it, without touching its size. Then check again and look at the FAILED. Deleting the file or emptying it so the check fails is not good enough: that is visible at a glance and proves nothing. What you have to see with your own eyes is that a file of the same size, looking the same and carrying the same date, collapses entirely over one changed letter in the middle. That is the whole reason a hash exists.

DELIVERABLE: the folder `~/cks-lab/p01/binario` holding the downloaded, executable kubectl binary, its kubectl.sha256 file exactly as the project published it, and the same-size kubectl-adulterado copy with one byte changed; plus the file `~/cks-lab/p01/04-respuesta.txt`, exactly 4 lines:

VERSION_DESCARGADA=<the version you downloaded, with the leading v>
SHA256_OFICIAL=<the 64 characters of the sum the project published>
RESULTADO_ORIGINAL=OK
RESULTADO_ADULTERADO=FALLA

<details>
<summary>What you should see</summary>

`kubectl get --raw /version` prints the server's JSON with major 1 and minor 36, and that is where the line comes from. The project's stable-1.36.txt file returns that line's latest stable, which on 2026-10-11 was v1.36.5; note it is not the same as the server version, v1.36.1, and that is fine, because kubectl supports one minor version of skew either way. The .sha256 is 64 bytes, that is the sum's 64 hexadecimal characters with no trailing newline, and the binary is over 50 MB (59584674 bytes on 2026-10-11). The first check prints kubectl: OK and exits 0. The second prints kubectl-adulterado: FAILED plus the line WARNING: 1 computed checksum did NOT match, and exits 1. And look at the ls: both files are the same size. One single byte changed in 50 MB, no change in size at all, and the whole sum collapses. ./kubectl version --client answers with the same version you downloaded (`Client Version: v1.36.5` on 2026-10-11).

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

- **Symptom (step 1):** The authorized neighbour arrives by IP but not by name
  **What to do:** You did not open egress to cluster DNS. Add a second entry to the egress policy's to list pointing at the kube-system namespace, by its kubernetes.io/metadata.name label, and inside it the podSelector k8s-app=kube-dns, with ports 53 UDP and 53 TCP. Confirm the namespace label with $K get ns kube-system --show-labels and the Pod's with $K -n kube-system get pods -l k8s-app=kube-dns --show-labels rather than typing them from memory.

- **Symptom (step 1):** After applying the rulebook, the stranger still gets in with exit code 0
  **What to do:** That is the lying watchman's symptom, and the first thing to rule out is the CNI. Confirm Calico came up with $K get tigerastatus and that the calico-system Pods are Running; if the cluster was created without disableDefaultCNI, the policies sit in the API and nobody enforces them. The second thing is that the policies are in the la-torre-tres namespace and not in default: a NetworkPolicy only acts inside its own namespace. And third, give it a few seconds: the CNI does not program the rules the instant you apply.

- **Symptom (step 1):** The stranger's wget hangs and never comes back
  **What to do:** You left out the timeout. A packet blocked by a NetworkPolicy does not bounce, it is dropped, so without -T the wget waits for the system default and you sit staring at the terminal. Use -T 5 as in this step's command; that bounded number is what turns the block into an exit code you can measure.

- **Symptom (step 2):** The kube-bench Job stays Pending and never starts
  **What to do:** The only node in this cluster is a control-plane node and carries the node-role.kubernetes.io/control-plane taint with NoSchedule, so a Pod with no toleration cannot be scheduled there. The manifest the setup left already carries the nodeSelector and the toleration; if you wrote your own by copying the project's job.yaml, add them. Confirm the exact cause with $K describe pod -l app=kube-bench and read the events.

- **Symptom (step 2):** I edited the manifest and the static pod does not change
  **What to do:** Check three things. That you edited the file inside the node container, in /etc/kubernetes/manifests, and not a copy on your machine. That the new line's indentation matches that of the other flags, four spaces and a dash: badly indented YAML makes the kubelet reject the file silently. And that you gave it time: the kubelet rescans the folder every few seconds. Look at the command that ended up running with $K -n kube-system get pod kube-scheduler-$NODO -o jsonpath='{.spec.containers[0].command}'.

- **Symptom (step 2):** I touched the API server and now kubectl does not answer
  **What to do:** That is expected for some thirty to sixty seconds: the API server's static pod is being recreated and there is nobody to ask. Wait and retry. If after a couple of minutes it still does not answer, the flag is misspelled: look at the container with docker exec $NODO crictl ps -a and its logs with docker exec $NODO crictl logs <id>, fix the manifest with sed and wait again. None of this needs a node restart.

- **Symptom (step 3):** curl says it cannot connect to port 8449
  **What to do:** That port only exists because the cluster was created with extraPortMappings. Confirm with docker port cks-p01-control-plane that host 8449 is mapped to the node's 443; if it does not show up, the cluster was created without the kind-p01.yaml file and has to be rebuilt, because extraPortMappings cannot be added to an existing cluster.

- **Symptom (step 3):** The served fingerprint does not match and the subject says Fake Certificate
  **What to do:** The controller did not find your Secret. Check in this order: that the Secret is in the same namespace as the Ingress, because secretName does not cross namespaces; that the name written in spec.tls[0].secretName is identical to the Secret's; that the Secret's type is kubernetes.io/tls and not Opaque; and that the rule's host also appears inside spec.tls[0].hosts, because the controller picks the certificate by the name arriving in the SNI. And give it a few seconds: the reload is not instantaneous.

- **Symptom (step 3):** kubectl apply of the Ingress fails with an admission webhook error
  **What to do:** ingress-nginx installs a ValidatingWebhookConfiguration that reviews every Ingress before accepting it. If the controller has not finished starting, that webhook does not answer and the apply fails. Wait for the controller Pod to be ready with $K wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s and apply again.

- **Symptom (step 4):** sha256sum --check says: no properly formatted checksum lines found
  **What to do:** The .sha256 file the project publishes carries only the sum, with no file name beside it, and sha256sum --check expects the format sum, two spaces, name. Build the line yourself before checking, as this step's command does. Mind the two spaces: with one it is not recognized either.

- **Symptom (step 4):** The downloaded binary is a few kilobytes
  **What to do:** You did not follow the redirect. dl.k8s.io answers with a redirect towards the real storage, so curl needs -L; without that flag you download the redirect page and not the program. Use -sSLO as in this step's command, delete what came down wrong and try again.

- **Symptom (step 4):** The check fails and I can see the file's sum does agree with the binary
  **What to do:** The local file agreeing with itself proves nothing, and that is precisely the lesson. The check asks dl.k8s.io for the sum again and compares against that. Confirm the version you declared is the one stable-<major>.<minor>.txt says today, because that line receives patches and may have moved since you downloaded; if so, download the binary and the sum again and update both lines of the answer file.

## Going further

- Add a fourth policy to tower three opening the authorized neighbour's egress outside the cluster, for example towards 1.1.1.1 on port 443, using an ipBlock instead of a podSelector. Then remove the except and put it back, and watch what happens when the excepted range overlaps Calico's IP pool range. It is the fastest way to understand why an egress policy written with CIDRs ages badly when the cluster network changes.
- Pick a second control from Step 2's fixable list, fix it too, and run kube-bench again. Write down how far the FAIL number dropped and how far the WARN number did not. Then read the remediation section kube-bench prints at the end for one of the controls left in WARN and explain in your own words why the tool cannot automate that check.
- Create a second TLS Secret with a certificate for another name, add a second host rule and a second tls block to the same Ingress, and confirm with openssl s_client that changing only -servername makes the same controller hand you two different certificates over the same port. That is SNI at work, and it is why the tls block carries a list of hosts and not a single host.
- Repeat Step 4 with the kubeadm binary of the same version, which is published under the same dl.k8s.io path with its own .sha256, and compare the two sums. Then find the artifact signature page in the official Kubernetes documentation and work out what a sigstore signature adds that a sha256 alone does not. The answer is the difference between integrity and provenance, and it is the one Chapter 12 will need.

## References

- Kubernetes Project, Network Policies. Documents podSelector, policyTypes, the ingress and egress rule lists, states that an empty podSelector selects all Pods in the namespace, gives the default-deny-all-ingress-and-egress recipe used in Step 1, and warns that network policies are implemented by the network plugin so that creating the resource without a controller that implements it has no effect. https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Kubernetes Project, Cluster Networking. States the model this lab measures as its Step 1 baseline: all Pods can communicate with all other Pods without NAT. https://kubernetes.io/docs/concepts/services-networking/
- Kubernetes Project, DNS for Services and Pods. Documents the service.namespace.svc.cluster.local form the authorized neighbour queries in Step 1, and therefore why an egress policy has to open port 53 towards the DNS Pods. https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Project Calico, release v3.32.1. The pinned CNI release used by this lab's setup, verified 2026-08-21 as the newest release of the v3.32 line. https://github.com/projectcalico/calico/releases/tag/v3.32.1
- Project Calico, Installation API reference. Documents the operator.tigera.io/v1 Installation resource and its calicoNetwork.ipPools fields, which this lab writes by hand instead of using the published custom-resources.yaml so the pool does not land on 192.168.0.0/16. https://docs.tigera.io/calico/latest/reference/installation/api
- Aqua Security, kube-bench. The tool Step 2 runs; its README documents the auto-detection of the Kubernetes version, the benchmark selection, the targets flag and the Job manifest with its host mounts that this lab pins by digest. https://github.com/aquasecurity/kube-bench
- Aqua Security, kube-bench release v0.16.0 (2026-08-05). The pinned release, verified against the GitHub releases API on 2026-08-21; its cfg directory is the source of the cis-1.12 benchmark this cluster auto-selects. https://github.com/aquasecurity/kube-bench/releases/tag/v0.16.0
- Center for Internet Security, CIS Kubernetes Benchmark. The control list kube-bench walks, and the source of the control numbering (1.2.15, 1.3.2, 1.4.1 and the rest) this lab's Step 2 quotes. https://www.cisecurity.org/benchmark/kubernetes
- Kubernetes Project, Static Pods. Explains that the kubelet watches a directory of manifests on the node and recreates the pod when a file changes, which is why Step 2's fix needs no restart of anything. https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
- Kubernetes Project, kube-apiserver command line reference. The authority on the --profiling and --service-account-extend-token-expiration flags Step 2 allows you to set. https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
- Kubernetes Project, kube-scheduler command line reference. The authority on the --profiling flag, the lowest-risk of the four fixes offered in Step 2. https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/
- Kubernetes Project, Ingress. Defines the Ingress resource and its tls block, states that the referenced Secret must contain the tls.crt and tls.key keys, and that TLS is terminated at the Ingress point. https://kubernetes.io/docs/concepts/services-networking/ingress/
- Kubernetes Project, Secrets. Documents the kubernetes.io/tls Secret type and the tls.crt and tls.key keys it requires, which is why an Opaque Secret carrying the same files is not enough for Step 3. https://kubernetes.io/docs/concepts/configuration/secret/
- Kubernetes Project, Ingress Controllers. States as its first prerequisite that you must have an Ingress controller to satisfy an Ingress and that creating the resource alone has no effect. https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/
- kubernetes/ingress-nginx, release controller-v1.15.1 (2026-03-19). The final release of the project, and the source of the kind provider manifest this lab pins; the repository itself is archived read-only, verified against the GitHub API on 2026-08-21. https://github.com/kubernetes/ingress-nginx/releases/tag/controller-v1.15.1
- Kubernetes Project, Install and Set Up kubectl on Linux. The source of the dl.k8s.io download URLs, of the stable-<major>.<minor>.txt lookup and of the sha256 verification procedure Step 4 performs, including the note that the checksum file carries only the sum. https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- Kubernetes Project, Version Skew Policy. States the supported skew between kubectl and the API server, which is why Step 4 accepts a patch release newer than the cluster's own server version. https://kubernetes.io/releases/version-skew-policy/
- kind Project, Configuration. Documents networking.disableDefaultCNI, networking.podSubnet and nodes[].extraPortMappings, the three settings this lab's cluster configuration depends on. https://kind.sigs.k8s.io/docs/user/configuration/
- kind Project, release v0.32.0. The source of the digest-pinned kindest/node:v1.36.1 image and of the instruction to pin node images by @sha256 rather than by tag. https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
