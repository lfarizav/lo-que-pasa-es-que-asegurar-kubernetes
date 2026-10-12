# Part IV - Lab: a set of house rules that is enforced at the gate, a safe you open from inside etcd to see what it stored, an employee in uniform who still works the shift, and an intercom that opens for nobody without an ID card

- Time: 55 min
- Points: 40

## Objective

This is an Exam-Style lab: every step gives you the objective and the deliverable, never the command, and the sequence that solves it lives in that step's cmd field for you to reveal once you have tried it with your own hands. Step 1 hands you a tower whose house rules sit at the loose level and a tenant manifest the gate rejects; you have to raise the rules to restricted and make the tenant fit inside them, and grading is not satisfied by seeing the Pod running: it re-measures the gate live by trying to push in two Pods that restricted has to reject, so dropping the level to baseline or privileged to make everything pass loses the step. Step 2 opens the corner store's safe from the side nobody looks at: you create a Secret and a ConfigMap holding the same text and go read both of them raw out of etcd, on the control-plane node, to confirm with your own eyes that no plaintext comes out of the Secret and plenty comes out of the ConfigMap; grading creates its own probe Secret at grading time and reads it back from etcd, so turning the cluster's encryption off to make something work fails the step. Step 3 puts the mandatory uniform on you: a Pod that does not run as root, whose filesystem root is read only, with not a single capability left, and which still writes its shift file every two seconds; grading does not just read the YAML, it enters the live container and asks the process who it is, which capabilities it kept and whether it can write to the root. Step 4 closes with Chapter 9's intercom: the complex's TLS server answers anybody today, and you have to make it demand a neighbor's ID card; grading measures the three calls that matter, with no card, with a card signed by another CA and with the good card, and requires the first two not to return 200 and the third to do so, because that is the only honest way to prove the verification is still in place.

## Prerequisites

- A Linux machine with kind, kubectl, docker and openssl on PATH, internet access to pull the images, and at least 4 GB of free RAM. This lab creates its own kind cluster named cks-p04, with a single node, and deletes it at the end. Everything goes through a private kubeconfig at ~/cks-lab/p04/kubeconfig, passed with --kubeconfig on every command: your usual kubeconfig is never touched, your current context never changes, and no other cluster of yours is affected. Do not run this lab against a production cluster.
- Versions this lab was run end to end with on 2026-10-11: kind v0.33.0, kubectl client v1.37.0, Docker 29.9.0, OpenSSL 3.0.13. Node image kindest/node:v1.36.1 pinned by digest sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, workload image busybox:1.37.0 by digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0, server nginx:1.29.3-alpine by digest sha256:b3c656d55d7ad751196f21b7fd2e8d4da9cb430e32f646adcf92441b72f82b14 and client curlimages/curl:8.19.0 by digest sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c. The etcdctl binary is not downloaded from the internet: it is taken out of the etcd image already living on the node, which on this kind image is registry.k8s.io/etcd:3.6.8-0. Confirm your kind with kind version and your kubectl with kubectl version --client rather than taking this paragraph's word for it.
- The cluster is born with Secret encryption at rest already configured, and that is deliberate. The setup generates a fresh 32-byte key on your own machine, writes an EncryptionConfiguration to ~/cks-lab/p04/enc/enc.yaml, mounts that directory inside the node and passes --encryption-provider-config to the kube-apiserver through kubeadmConfigPatches. The key is generated on every install and never version-controlled: if you delete the workspace, the key goes with it and the old cluster can no longer read its own Secrets, which is what happens in real life when somebody loses the key to the safe.
- The setup does not just build the cluster: it runs four substrate tests on it before letting you start, because all four steps assume behaviors a cluster can accept over the API and never enforce. It checks that Pod Security Admission rejects what restricted forbids (and that baseline did let it through, so the difference is measured and not asserted), that a freshly created Secret lands encrypted in etcd, that the kubelet enforces readOnlyRootFilesystem and the drop of every capability, and that the TLS intercom answers over the cluster network. If any of them fails, the setup prints a named error and stops, because a lab that grades a control nobody enforces is decoration.
- Having read Chapters 7, 8 and 9. This lab does not re-explain the three Pod Security Standards levels, the difference between base64 encoding and encryption, or why an intercom with no mutual authentication isolates nothing; it makes you operate all three against a real cluster and grades them against its real state.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 7: Tower A's house rules move up to restricted, and the tenant has to fit inside them (10 pts)

Chapter 7 explained that the complex's rules of coexistence have three levels and that what matters is not having them pinned to the noticeboard but having the gate enforce them. Here you get to live it: tower A has its rulebook set to the middle level, somebody left you a ready-to-apply tenant manifest, you apply it in good faith, and the gate hands it straight back to you.

This rejection is not a whim. The message Pod Security Admission returns is one of the most generous Kubernetes gives, because it tells you three things at once: which level was being enforced, which version of that level, and which Pod field broke which rule. Read the whole thing before touching anything, because when you raise the rulebook to restricted the message changes and hands you the complete list of the missing uniform.

A point that costs dearly on exam day: Pod Security Admission is admission, meaning it acts at the moment an object comes in, and only there. If you label a namespace where Pods are already violating the new level, those Pods keep running without a problem and all you get is a warning on the console. The label evicts nobody. That is why raising the level on a live namespace is not a cleanup action, it is a containment action going forward.

The easy way out is not to loosen the rulebook. Lowering the enforce label to baseline, lowering it to privileged or deleting it gets the tenant in within three seconds and gets you a failed step, because the tenant got in but the tower is left with no gate. Grading does not take the label's word for it: at grading time it pushes in two probe Pods of its own, one ordinary and one privileged, and both have to bounce. If they bounce, the rulebook exists; if they pass, you dismantled it.

DELIVERABLE: the `pod-security.kubernetes.io/enforce` label on the `torre-a` namespace set to `restricted`, the `pod-security.kubernetes.io/enforce-version` label present and non-empty, the `inquilino` Pod running and Ready in that namespace with no `privileged`, and the file `~/cks-lab/p04/01-respuesta.txt`, exactly 2 lines:

```text
NIVEL_APLICADO=<the level left in the torre-a namespace's enforce label>
USUARIO_DEL_INQUILINO=<the uid the process runs as, read from inside the container>
```

<details>
<summary>What you should see</summary>

The first apply, with the tower still on baseline, crashes and the error names the broken rule: Error from server (Forbidden): error when creating "inquilino.yaml": pods "inquilino" is forbidden: violates PodSecurity "baseline:latest": privileged (container "inquilino" must not set securityContext.privileged=true). After raising the label to restricted, the same manifest fails again but now the message says violates PodSecurity "restricted:latest" and carries five broken rules instead of one: the same privileged as before, plus allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true and seccompProfile. Those four new ones are the uniform the tenant is missing: what restricted demands and baseline did not. With the manifest fixed, the apply creates the Pod, the wait returns pod/inquilino condition met, the jsonpath prints nivel=restricted and version=latest, and the exec prints 1000, which is the uid you chose and not the 0 the image shipped with. If you picked a different non-zero uid, that number is yours and that is the one that goes in the answer file.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 8: The corner store's safe, opened from inside etcd (10 pts)

Chapter 8 told you the corner store's safe is not as strong as it sounds. Here you open it yourself, but not through the front door, which is kubectl get secret, but from behind: getting onto the control-plane node and reading etcd directly, which is what somebody who stole the disk would do.

This cluster was born with encryption at rest already in place. Nobody is going to hand it to you that way on the exam, but for today's purposes it works better, because it lets you make the comparison that teaches: store the same text in a Secret and in a ConfigMap, and go see which of the two shows up readable on the node's disk. This machine's EncryptionConfiguration covers secrets and does not cover configmaps, and that resource list is a decision somebody made and that you can read in the mounted file.

And there is a plumbing detail that will cost you ten minutes if you do not know it: etcdctl does not ship in kind's node image. The etcd container is distroless and has no shell, so there is no getting in there to look for it. But the etcd image does live in the node's containerd store, and the node does have ctr, so the binary comes out of the image without downloading anything from the internet. The setup already left it at /usr/local/bin/etcdctl so you do not spend your shift on that, but know where it came from.

One confusion worth clearing up: base64 is not encryption. When you run kubectl get secret -o yaml and see a stream of odd characters, that is encoding, it comes undone with a one-line command and it protects nothing. The only thing that makes any difference between a Secret and a ConfigMap in front of somebody holding the node's disk is whether an EncryptionConfiguration covers that resource. Without one, both are plain text on disk and the only real difference left is who can read them through RBAC.

DELIVERABLE: the `caja-fuerte` Secret and the `aviso-de-la-tienda` ConfigMap in the `tienda` namespace, both carrying the `clave` key with the exact value `la-plata-de-la-tienda-2026`, and the file `~/cks-lab/p04/02-respuesta.txt`, exactly 3 lines:

```text
SECRETO_CIFRADO_EN_ETCD=<true if the raw read of the Secret does not show the value in the clear, false if it does>
CONFIGMAP_EN_CLARO_EN_ETCD=<true if the raw read of the ConfigMap does show the value in the clear, false if it does not>
PREFIJO_DEL_PROVEEDOR=<the complete prefix, trailing colon included, that precedes the Secret's ciphertext in etcd>
```

<details>
<summary>What you should see</summary>

The grep on the kube-apiserver manifest prints line 43 with --encryption-provider-config=/etc/kubernetes/enc/enc.yaml, which is the proof that the kubeadm patch was in place from the cluster's birth. The cat of the mounted file shows the EncryptionConfiguration with an aescbc provider whose key is named llave-de-la-caja and an identity fallback provider behind it. The raw read of the Secret prints the key /registry/secrets/tienda/caja-fuerte and, on the next line, text starting with k8s:enc:aescbc:v1:llave-de-la-caja: followed by binary garbage: that is ciphertext and there is no way to read the password out of it. The raw read of the ConfigMap prints readable protobuf instead, where you can see clave followed by la-plata-de-la-tienda-2026 in plain text, with no dressing at all. The three closing greps print k8s:enc:aescbc:v1:llave-de-la-caja:, then 0 (the password text does not appear even once in the Secret's dump) and then 1 (it does appear in the ConfigMap's). That asymmetry is the whole of Chapter 8 in three lines: this cluster's EncryptionConfiguration covers secrets and does not cover configmaps, and whatever you put into the wrong object is written to the node's disk as you typed it.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 7: The mandatory uniform, and the employee who still works the shift (10 pts)

Chapter 7 introduced the rulebook's fields one by one. This step puts them to work together and asks the only question that matters after hardening anything: does it still work?

The mandatory uniform is three garments and each one covers a different attack path. Not running as root strips the process of the identity that would let it touch anything if it broke out of the container. A read-only root stops it from leaving a binary, a cron job or a modified library inside the image, which is the classic next step after a remote execution. And dropping every capability takes away even the odd permissions the runtime hands out out of habit and that your application does not need.

The third garment is easy to get wrong, and not because it is hard but because it is careless. When you mount the root read-only, the application that used to write to /tmp stops starting, and the reflex is to take the garment off. The correct reflex is the opposite: give the application a place where it can write, mounted separately, and leave the root shut. An emptyDir mounted at /tmp costs three lines and gives the application its place to write. That technique, the /tmp probe, is what separates a hardened Pod from a switched-off Pod.

You can lose this step from either side. If you loosen the uniform so the employee can work, you lose. If you leave the uniform perfect but the employee stands still, you also lose, because grading looks at the shift file twice five seconds apart and requires the timestamp to have changed. Hardening is not switching off. A hardened container that no longer does anything is an incident with better press.

DELIVERABLE: the `empleado` Pod running and Ready in the `apartamento-303` namespace, on a busybox image, not running as root, with a read-only filesystem root, with every capability dropped, and writing the time into `/tmp/turno.txt` every two seconds without stopping. And the file `~/cks-lab/p04/03-respuesta.txt`, exactly 3 lines:

```text
UID_DEL_PROCESO=<the uid id -u reports inside the container>
CAPEFF_DEL_PROCESO=<the CapEff value /proc/1/status reports inside the container, verbatim, with all its zeroes>
ESCRITURA_EN_LA_RAIZ=<denegada or permitida, depending on what happens when you try to create a file at the root>
```

<details>
<summary>What you should see</summary>

The Pod starts and goes Ready. The id -u prints 1000, or whichever non-zero uid you picked. The CapEff grep prints CapEff: 0000000000000000, that is sixteen zeroes: the process kept not one capability, not even the ones Docker leaves by default. The touch on the root fails with touch: /prueba-en-la-raiz: Read-only file system and ends with salida=1. The /proc/mounts grep shows two lines that explain why the Pod keeps working: the root shows up as overlay / overlay ro,relatime,... and /tmp shows up as a separate filesystem mounted rw. The two cats print different timestamps a few seconds apart, because the loop keeps writing its shift file in the only place it can. That is the entire point of the step: a read-only root is not a padlock that switches the application off, it is a padlock that forces it to say out loud where it needs to write.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 9: The intercom that opens for nobody without an ID card (10 pts)

Chapter 9 ended with the encrypted intercom, and this is where you see that encrypted does not mean secure. The complex's intercom already speaks TLS: traffic between the neighbor and the server travels encrypted and nobody listening in the hallway understands it. And even so, today it opens for anybody who rings, because encrypting the conversation and knowing who you are talking to are two different problems.

In ordinary TLS the one who shows ID is the server, not the client. That is why your browser knows it is talking to the bank, but the bank does not know it is you until you log in from inside. Mutual TLS is simply demanding ID on both sides: the server still presents its own and on top of that asks the client for one, signed by a CA it recognizes. In the complex that is the resident's ID card: you do not get in because the intercom sounds nice, you get in because the guard recognizes who signed your card.

There is no service mesh and no sidecars here, and that is on purpose: this step is graded by measuring three calls, not by reading a product's documentation. And there is one measurement that is easy to overlook, the one that proves the verification exists: presenting a well-formed card signed by a different CA. A misconfigured server, one of those that asks for a certificate but does not validate it against any authority, opens for that fake card as it does for the good one, and whoever only tested "no card fails, card works" goes home believing they isolated something.

Switching the intercom off is not locking it. Deleting the server's Pod does make the call with no card fail, yes, but the call with the card fails too, and an intercom that will not answer even the resident is not a security measure, it is damage. Same with setting ssl_verify_client to optional so the errors stop: that is writing the word without doing the thing. Grading measures the three calls and on top of that reads the live configuration inside the container, so the word has to be there and the thing has to happen.

DELIVERABLE: the intercom demanding a client certificate validated against the complex's CA, with both the `citofono` and `vecino` Pods Running, and the server's greeting showing the CN of the certificate the client presented. And the file `~/cks-lab/p04/04-respuesta.txt`, exactly 3 lines:

```text
SIN_CARNET=<the HTTP code of a call to the intercom presenting no client certificate>
CARNET_DE_LA_CALLE=<the HTTP code of a call presenting the certificate signed by the street's CA>
CON_CARNET=<the HTTP code of a call presenting the neighbor's card>
```

<details>
<summary>What you should see</summary>

Before touching anything, the first call to the intercom returned 200 with no card presented, which is what the setup had already told you: the intercom exists, speaks TLS and opens for anybody. After demanding a card and recreating the Pod, the three measurements change to sin_carnet=400, carnet_de_la_calle=400 and carnet_del_vecino=200. The first two come out 400 and not 403 nor a connection failure because the TLS handshake does complete and it is nginx that then answers with Bad Request and the body No required SSL certificate was sent; note that curl exits zero in that case, so looking at curl's exit code grades nothing, which is why the HTTP code is what gets measured. The last call prints the body citofono del 303: adelante, CN=apartamento-303, and you did not write that CN: nginx pulled it out of the certificate the client presented, which proves the server did not merely ask for the card but read it and validated it against the complex's CA. On the machine where this lab was executed the Service endpoint took a few seconds to propagate after recreating the Pod; if your first measurement comes out 000, wait and repeat.

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

- **Symptom (step 1):** The Pod is rejected with runAsNonRoot != true even though you already set runAsNonRoot: true
  **What to do:** Look at where you put it. The Pod's securityContext and the container's securityContext are two different objects with different fields, and several fields exist in only one of them. runAsNonRoot, runAsUser and seccompProfile live at both levels, but allowPrivilegeEscalation and capabilities exist only on the container's. If the rejection persists, read the whole message: it names the container in quotes right before the broken rule, and that tells you whether it is talking to the Pod or to one specific container. The field reference is at https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

- **Symptom (step 1):** The Pod is admitted but sits in CreateContainerConfigError and never starts
  **What to do:** That is no longer an admission problem but a kubelet one: you set runAsNonRoot to true but never said which uid to run as, and the image declares no non-root user. The API server admits the Pod because the field is correctly set; the kubelet, on going to start the container, discovers the image wants to run as uid 0 and refuses. Read the verbatim reason with kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n torre-a describe pod inquilino and add a non-zero runAsUser.

- **Symptom (step 2):** etcdctl answers context deadline exceeded or returns nothing
  **What to do:** There are two possible causes. Either you forgot to tell it which endpoint to talk to and which certificates to present: kubeadm's etcd listens on https://127.0.0.1:2379 and demands a client certificate, and the ones that work are in /etc/kubernetes/pki/etcd/ inside the node. Or the key path is misspelled: in etcd, Kubernetes objects live under /registry/<plural resource>/<namespace>/<name>, so a Secret named caja-fuerte in the tienda namespace is at /registry/secrets/tienda/caja-fuerte and not at /registry/secret/... If you are unsure of the path, list the keys under a prefix with --keys-only instead of guessing. The full procedure is at https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/

- **Symptom (step 2):** The Secret's dump comes out full of control characters and the terminal goes haywire
  **What to do:** It is ciphertext, meaning binary bytes, and that is what was expected: the terminal is trying to interpret them as escapes. Pipe it through cat -v to see them as printable sequences, or grep it instead of staring at the whole thing, which is what you need anyway: grep -oa to pull out the prefix and grep -ca to count how many times the plaintext appears. The -a flag is the one that tells grep to treat a binary file as text; without it grep answers Binary file matches and you see nothing.

- **Symptom (step 3):** The container drops into CrashLoopBackOff the moment you set readOnlyRootFilesystem to true
  **What to do:** The application is trying to write somewhere in the image and now cannot. The answer is not to remove the flag but to find out where it writes and mount a writable volume there. Look at the crashed container's logs with kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n apartamento-303 logs empleado --previous: the error names the path it tried to write to. Then mount an emptyDir at that path. If there are several paths, mount several emptyDirs; it is still safer than opening up the whole image.

- **Symptom (step 3):** CapEff does not come out as zeroes even though you set drop ALL
  **What to do:** Check two things. First, where you put capabilities: that field exists only in the container's securityContext, never in the Pod's, and if you write it in the Pod's the API server either rejects it or ignores it depending on the version. Second, whether you left an add next to the drop: the add list is applied after the drop list, so drop ALL plus add NET_BIND_SERVICE leaves that capability in place and CapEff does not come out as zeroes. And third, check that you are reading /proc/1/status and not /proc/self/status from an exec: the exec's process can hold a different set from the container's main process.

- **Symptom (step 4):** You changed the ConfigMap but the intercom keeps opening for anybody
  **What to do:** The intercom's file is mounted with subPath, and a subPath mount is never updated when the ConfigMap changes. That is a Kubernetes design decision, not a bug: the kubelet only refreshes the content of a ConfigMap volume mounted as a directory. On top of that, even if the file did refresh, nginx reads its configuration at startup. Both are solved the same way: delete the server's Pod and recreate it from the manifest the setup left at ~/cks-lab/p04/citofono-pod.yaml. Confirm the live configuration changed with kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono exec citofono -- cat /etc/nginx/conf.d/citofono.conf before measuring again.

- **Symptom (step 4):** All three calls return 000 and curl says it could not connect
  **What to do:** curl's 000 is not an HTTP code: it means there never was a response. After deleting and recreating the server's Pod, the Service needs a few seconds to point at the new Pod again, and in the meantime the calls fail at the connection level. Check who the Service points at now with kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono get endpointslices and repeat once an address shows up. If the endpoint is there and it still will not connect, look at whether nginx started: kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono logs citofono, because a syntax error in the configuration makes the container die instead of serving.

## Going further

- Go back to Step 1 and instead of raising one namespace's level, put the Pod Security Admission labels in warn and audit mode on every namespace in the cluster with enforce on none of them, then create Pods that violate restricted. You will see warnings arrive on the console and entries in the audit log without anything being blocked. That is the real way to raise the level on a cluster with tenants: first you measure who would break, then you enforce. Compare how many kube-system Pods would violate restricted and draw your own conclusion about why the level is not raised in one go.
- Go back to Step 2 and rotate the key. Add a second key to the EncryptionConfiguration's aescbc provider, put it first, let the kube-apiserver pick it up, and read the caja-fuerte Secret out of etcd again: it will still be encrypted with the old key, because rotating the key does not rewrite what was already stored. Then make it be rewritten and check that the prefix's key name changed. That step is easy to forget when you have to rotate for real, and it is the difference between believing you rotated and having rotated.
- Go back to Step 4 and change ssl_verify_client from on to optional_no_ca, recreate the Pod and make the three calls again. You will see that the card signed by the street's CA now gets in like the good one, and that the call with no card still fails: the configuration asks for a certificate but validates it against nobody. Record the three codes and compare them against the graded step's. That configuration can be presented as mTLS and it isolates nothing.

## References

- Kubernetes Project, Pod Security Admission. Primary source for the pod-security.kubernetes.io/enforce and enforce-version labels Step 1 sets, for the fact that the controller acts only at admission and never evicts running Pods, and for the shape of the violates PodSecurity rejection message the step reads. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Kubernetes Project, Pod Security Standards. Primary source for the exact field list the restricted level demands and the baseline level does not (allowPrivilegeEscalation, capabilities drop ALL, runAsNonRoot, seccompProfile), which is what makes Step 1's before-and-after rejection messages differ. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Kubernetes Project, Encrypting Confidential Data at Rest. Primary source for the EncryptionConfiguration file format the setup writes, for the --encryption-provider-config flag passed through kubeadm, for the resource list semantics that make secrets covered and configmaps not, and for the etcdctl verification recipe with the k8s:enc: prefix that Step 2 executes. Verified 2026-08-21. https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
- Kubernetes Project, Configure a Security Context for a Pod or Container. Primary source for runAsNonRoot, runAsUser, readOnlyRootFilesystem and capabilities, and for which of those fields exist on the Pod's securityContext versus the container's, which is where Step 3's field-placement errors come from. Verified 2026-08-21. https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Kubernetes Project, Security Checklist. Primary source for the cluster-level hardening items this lab exercises hands-on: Pod Security Standards enforcement per namespace, encryption of Secrets at rest, and the recommendation to terminate TLS with mutual authentication between workloads. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/security-checklist/
- nginx Project, Module ngx_http_ssl_module. Primary source for ssl_verify_client, ssl_client_certificate and the $ssl_client_s_dn variable Step 4 configures and reads, including the difference between on, optional and optional_no_ca that Step 4's third measurement is designed to detect. Verified 2026-08-21. https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- kind Authors, Configuration. Primary source for the kubeadmConfigPatches and nodes[].extraMounts fields the setup uses to bring the cluster up with an EncryptionConfiguration already mounted and already referenced by the kube-apiserver, and exercised with kind v0.33.0 on 2026-10-11. Verified 2026-08-21. https://kind.sigs.k8s.io/docs/user/configuration/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
