# Part V - Lab: the storeroom that goes on a diet, the box ordered by receipt instead of by nickname, the supplier who brings the pest inside, and the seal the door guard checks

- Time: 55 min
- Points: 40

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and that step's exact command sequence lives in its cmd field for you to reveal after you have tried on your own. The four steps walk the CKS Supply Chain Security domain end to end, and all four are graded by measuring the real world, not by reading what you typed. Step 1 hands you a bloated Dockerfile that leaves the whole compiler inside the production image, and demands you convert it into a multi-stage build whose final image lands under a stated size and still serves the menu over HTTP: both are measured, the first with docker image inspect and the second by starting the container and asking it for the page (Chapter 10). Step 2 hands you a Deployment that asks for its image by tag, that is by nickname, and demands you repin it by digest; the check goes to the live registry, asks what that tag's digest is today, and compares it against the Deployment spec and against the imageID the kubelet reports on every Pod, so one loose tag anywhere in the namespace fails you (Chapter 11). Step 3 puts two candidate images from two different suppliers in front of you and demands you find with trivy which of the two carries a CRITICAL vulnerability inside, deploy only the clean one, and record the CVE identifier; the check re-scans both with the same pinned trivy and demands that the CVE you named is present in the rejected one and absent from the approved one (Chapters 10 and 11). Step 4 closes with cosign against a local registry: you generate your key, sign the approved image, and write an admission policy that demands that seal at the door; the check verifies the signature with cosign outside the cluster, confirms the unsigned image does not verify, and then creates live Pods to watch the signed one get in with its digest pinned on while the unsigned one stays outside (Chapter 12). Deleting the policy so it stops complaining fails the step, and signing the dirty image too so that everything passes fails it just the same.

## Prerequisites

- A Linux machine with docker, kind, kubectl, helm, jq and curl on `PATH`, internet access during setup, and at least 4 GB of free RAM. The lab creates its own kind cluster named cks-p05, its own local registry in the container cks-p05-registry published on 127.0.0.1:5065, and deletes both in the teardown.
- Isolation: this is not a matter of style. This lab's cluster never touches your everyday kubeconfig: it is created with --kubeconfig ~/cks-lab/p05/kubeconfig from the very first command, and every kubectl and helm in the lab passes --kubeconfig and --context explicitly. If you already have other kind clusters running on this machine, this lab does not see them, does not modify them and does not delete them. Check it yourself: the setup ends by printing a kubectl config get-contexts with no --kubeconfig, and cks-p05 must not show up there at all. The registry is its own too: unique name and unique port, so it cannot land on top of any other local registry you have running.
- Patience with the setup: it downloads the kind node image, the registry image, the golang image which weighs close to 1.3 GB on disk, two .jar files from the Maven central repository, the cosign binary, the trivy binary and trivy's vulnerability database, and on top of that installs Kyverno with helm. On a machine starting from scratch that is between 10 and 20 minutes. That time is substrate, it does not count towards your grade; the lab's 55 minutes are the four graded steps.
- Pinned versions and digests; the lab was run end to end on 2026-10-11 on this same machine with kind v0.33.0, kubectl client v1.37.0, Docker 29.9.0 with the containerd snapshotter and helm v4.3.0. Also: jq 1.7. cosign v2.6.5, the series that still signs without transparency using --tlog-upload=false. trivy v0.74.0. Kyverno chart 3.9.0, application v1.19.0. Node image kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5. Registry registry:3@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33. Fat base golang:1.25@sha256:fe5d57d3b718e7a4986bae156c2d73f44973bfd313073aed08a4de6692bb6161. Suggested slim base alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce. A tag is mutable and a digest is not: that is why everything here is pinned and why Step 2 exists at all. Confirm what you got installed with kind version, kubectl version and docker version, never from memory.
- Having read Chapters 10, 11 and 12. This lab does not re-explain why a small base image gives a thief less to work with, or what a digest is, or how cosign stores a signature in a registry; it makes you operate all three against a real cluster and a real registry, and grades the end state.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 10: The storeroom does not go up to the storefront, and the compiler does not ship with the bread (10 pts)

Chapter 10 explained the idea with the corner store: the more stock sitting in the back room, the more there is to steal, and the stock sitting there is not needed to sell bread. Here's what's actually going on: in the container world you build that back room without noticing, because the most natural Dockerfile in the world is the one that compiles and ships in the same place.

Open the `Dockerfile.bodega` the setup left you. It is a single stage. It starts from the official Go image, which carries the compiler, the linker, git, the full standard library and a whole operating system underneath. It compiles your program. And it ships that very image to production. The binary you need weighs a few megabytes; what is going to travel to the cluster weighs hundreds.

That is not "a bit of extra weight". That is attack surface. Every compiler left inside is a tool an attacker no longer has to upload. Every `curl`, every `wget`, every shell, every package manager is a step you left in place for them. And every package in the base system is a potential CVE that will show up in the Step 3 scan without your code having anything to do with it.

Multi-stage builds exist for this: one stage that compiles with every tool in the world, and a final stage that starts from nothing and into which you copy only the result. What is not copied does not exist. And when the final stage is `scratch`, what remains inside is a single file: your binary. No shell, no package manager, nothing to open.

One practical detail so it does not fall over on you: `scratch` carries no system libraries, so the binary has to be static. `Dockerfile.bodega` already left `CGO_ENABLED=0` in place, which is what makes Go compile without linking against the system libc. If you decide to use `alpine` instead of `scratch` it will work too and will land under the limit, with the advantage of having a shell to debug with and the disadvantage of having a shell for somebody else to debug with.

DELIVERABLE: the image `la-tienda:flaca`, built from `~/cks-lab/p05/la-tienda/tienda.go`, with the executable at `/tienda`, a size reported by `docker image inspect` under 26,214,400 bytes (25 MiB), with no Go compiler inside, serving the menu at the root of port 8080 and the Go version at `/version`. The image `la-tienda:bodega` must not be deleted: the step compares the two. Plus the file `~/cks-lab/p05/01-respuesta.txt`, exactly 4 lines:

```text
TAMANO_BODEGA=<bytes docker image inspect reports for the bloated image>
TAMANO_FLACA=<bytes docker image inspect reports for your final image>
CARTA_QUE_SIRVE=<the line the container returns at the root of port 8080>
VERSION_DE_GO=<the line the container returns at `/version`>
```

<details>
<summary>What you should see</summary>

The Dockerfile.bodega the setup left you has a single stage: it starts from digest-pinned golang:1.25, compiles the binary inside, and ships that very image to production with the compiler, the linker, git and the whole Go standard library still in place. docker image inspect on it returned 1,366,669,432 bytes on 2026-10-11 (about 1.37 GB), and docker image ls may show a different figure in its `DISK USAGE` column, because those are two different ways of measuring the same image; the lab grades on the inspect number, which is the one that does not depend on what else you have on disk. After the conversion to a multi-stage build with a scratch final stage, that same inspect returned 7,989,501 bytes: the image came out about 171 times smaller and it is still the same program. The container starts with no shell, no package manager and nothing but an executable, and curl still hands you pan-de-la-esquina-v1 at the root and go1.25.12 (the value observed on 2026-10-11) at `/version`. That second endpoint is what proves what is running is a compiled Go binary and not a text file being served from somewhere.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 11: The box is ordered by receipt, not by nickname, because the nickname gets changed without telling you (10 pts)

Chapter 11 told you about the receipt: the store needs to know where every box came from, and to know it in a way the supplier cannot change afterwards. An image tag is not a receipt, it is a nickname. `pan:v1` does not mean "this box"; it means "the box that is called v1 today". And whoever has write access to that repository can push something else under that same nickname tonight, without telling anybody, and tomorrow your Deployment starts a new Pod with different content and the same YAML.

You are not safe because the Pod is already running. You are safe until it restarts. The day that node goes down, or you scale, or the kubelet reschedules, the new container comes from the nickname, not from the one you reviewed.

A digest is a receipt. It is the manifest's hash: change one byte of the content and the digest changes, and a `repository@sha256:...` reference that no longer matches simply cannot be resolved. There is no way to replace the content while keeping the same digest.

And here is a detail that is easy to miss. Look at the `imageID` of the Pods already running, before you touch anything. It already says a digest. The kubelet always resolves the nickname to a digest and runs that digest. Which means the digest was always there; the only thing that changes when you write it into the spec is who decides which one it is: you, or whoever holds the key to the repository.

This step asks you to convert the storefront. The answer to "which digest" is not something you invent: you ask the registry, which is the source.

DELIVERABLE: the `la-vitrina` Deployment in namespace `la-vitrina` asking for its image by digest, with 2 ready replicas, and no Pod in the namespace asking for an image by tag. The digest has to be the one the registry reports today for `tienda/pan:v1`. Plus the file `~/cks-lab/p05/02-respuesta.txt`, exactly 3 lines:

```text
DIGEST_DEL_REGISTRO=<the digest the registry reports for tag v1>
IMAGEN_DEL_DESPLIEGUE=<the full reference that ended up in the Deployment spec>
REPLICAS_LISTAS=<how many replicas the Deployment reports as ready>
```

<details>
<summary>What you should see</summary>

Before you touch anything, the Deployment spec says cks-p05-registry:5000/tienda/pan:v1, a nickname, and yet every Pod's imageID already says cks-p05-registry:5000/tienda/pan@sha256:caef363d... Look carefully at that asymmetry, because it is the whole idea of the chapter: the kubelet always ends up running a digest, you are the one who chose not to write it down. The `HEAD` request to the registry returns a Docker-Content-Digest header with that same sha256, which is the answer to the question of what the nickname points to today. After the set image the rollout starts new Pods, and now the spec and the imageID say the same thing. The image has no tag anywhere any more: it says repository@sha256:..., and nobody can swap that from under you, because if they change the content the digest changes and you are the one carrying the digest in writing.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 11: Two suppliers bring the same box, and one of the two brings it with a pest inside (10 pts)

Chapter 11 left you with an uncomfortable idea: the box can arrive sealed, with a receipt, from your usual supplier, and carry the pest inside. You did not pack what is inside the box. Somebody else packed it, months ago, and all you did was write one line saying you want it.

The setup left you two candidate images in the lab registry, `tienda/proveedor-a:2026-08` and `tienda/proveedor-b:2026-08`. From the outside they are identical: same base, a very similar size, same command. Inside, each one carries a packaged event-logging library, and one of the two comes from an old batch. Which is which is not decided by your intuition or by the supplier's name: it is decided by the scanner.

Looking at the base image is not enough. Both images come off the same alpine and both will report zero operating-system vulnerabilities. The finding is not in the system, it is in a `.jar` file somebody copied inside. A serious scanner does not stop at system packages: it walks into language-level packaged dependencies, and that is where the truth shows up.

And a precision about words, because they matter on the exam. A vulnerability is not the same thing as a risk. Trivy reporting CRITICAL means that version of that library has a known defect of critical severity, not that your application is exercising it. But at a cluster's door, hands on the keyboard and the clock running, the policy is simple: the box with a critical does not go up on the shelf.

This step asks you to act as the buyer: scan both, decide on evidence, deploy only the good one, and put in writing which defect made you reject the other.

DELIVERABLE: in namespace `la-bodega`, a Deployment named `el-proveedor` with 2 ready replicas running only the clean supplier's image, and no copy of the rejected supplier's image running in that namespace. Use the name `cks-p05-registry:5000` so the cluster resolves the registry. Plus the file `~/cks-lab/p05/03-respuesta.txt`, exactly 3 lines:

```text
CVE_CRITICO=<the CVE identifier, uppercase, of a CRITICAL vulnerability trivy reports in the rejected image and does not report in the approved one>
PROVEEDOR_RECHAZADO=<the repository of the supplier you rejected, in the form tienda/proveedor-X>
PROVEEDOR_APROBADO=<the repository of the supplier you deployed, in the form tienda/proveedor-X>
```

<details>
<summary>What you should see</summary>

The first scan hands you a summary table with two rows: the image's operating system, alpine 3.22.5, with 0 vulnerabilities, and a second row reading opt/despacho/lib/log4j-core-2.14.1.jar of type jar, with 2. Read that slowly, because it is the step's lesson: the base was spotless and the pest came inside a dependency packed into the box. The detail table names CVE-2021-44228 and CVE-2021-45046, both CRITICAL, both against org.apache.logging.log4j:log4j-core at installed version 2.14.1, and tells you which versions fix it. The second scan, the other supplier's, returns the same structure with 0 and 0: same operating system, same library, different version, no criticals. Then the clean box's Deployment ends with 2 ready replicas and its Pods' imageID points at that image's digest.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 12: The seal of approval is worth nothing if the door guard does not check it (10 pts)

Chapter 12 closed the part with the idea that ties it all together: you already know how to slim the box, how to order it by receipt and how to inspect it for pests. What is missing is the authorized supplier's signature, and somebody at the door who checks it. The second half of that sentence is easy to skip.

Signing is easy: `cosign sign` with your private key, and done. And there is a detail worth knowing: the signature does not land in a file next to the image. It is pushed to the same registry, as one more artifact, under a tag derived from the signed image's digest. Which means the signature travels with the box, not in a separate drawer, and that is why anybody who can read the repository can verify it without asking you for anything.

But signing on its own protects nothing. A signature nobody verifies is a sticker. The real control is at the door: an admission webhook that, before letting any Pod in, takes the image reference, goes to the registry, looks for the signature, verifies it against the public key you declared to it, and if it does not add up rejects the Pod's creation. Without that guard you can sign every image in the world and the cluster will keep running whatever it is handed.

There is a hidden gift in that rule, and it is why this step closes the whole part: when verification passes, the webhook rewrites the image reference to pin it to the exact digest it just verified. Which means the signature policy also imposes Step 2's discipline, automatically, without anybody having to remember. Verifying by tag would be absurd: if the tag can be moved, verifying the tag verifies nothing.

A warning about this lab's signature: it is made with `--tlog-upload=false`, with no public transparency log, because your registry is local and there is nowhere to publish. That is why verification has to be told explicitly to ignore the log, and why the policy needs `rekor.ignoreTlog`. In production with public Sigstore it is the other way around, and that asymmetry is worth seeing with your own hands.

The approved box is the one you approved in Step 3. This step depends on that conclusion.

DELIVERABLE: a cosign key pair at `~/cks-lab/p05/despacho.key` and `~/cks-lab/p05/despacho.pub`; the approved supplier's image signed by digest with that key in the lab registry, and the rejected supplier's image left unsigned; a ClusterPolicy with a `verifyImages` rule in Enforce demanding that key for images `cks-p05-registry:5000/tienda/*` arriving in namespace `el-deposito`; and in that namespace a Pod named `el-aprobado` running the approved image. Plus the file `~/cks-lab/p05/04-respuesta.txt`, exactly 2 lines:

```text
POLITICA_VERIFY=<the name of the ClusterPolicy that demands the signature>
DIGEST_FIRMADO=<the sha256 digest of the image you signed>
```

<details>
<summary>What you should see</summary>

generate-key-pair writes despacho.key and despacho.pub without asking for a password because COSIGN_PASSWORD is empty. The sign ends with a line reading Pushing signature to: 127.0.0.1:5065/tienda/proveedor-b, and that is literal: the signature does not go into a separate file, it goes into the same registry, stored as one more artifact under a tag derived from the digest in the form sha256-<digest without prefix>.sig. verify on the signed one succeeds; on the unsigned one it ends in an error with a message reading no signatures found. Applying the ClusterPolicy will print a warning that ClusterPolicy is deprecated and that you should migrate to the policies.kyverno.io policies (for example ImageValidatingPolicy): it is a warning, not an error, and on the 3.9.0 chart this lab pins the rule works. Then the el-aprobado Pod is created, and reading it back from the cluster its image no longer ends in :2026-08 but in :2026-08@sha256:..., because mutateDigest pinned the exact digest Kyverno just verified. And the el-rechazado Pod is not created: the server answers with an error from the mutate.kyverno.svc-fail webhook reading failed to verify image ... no signatures found. That error is the step passing, not failing.

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

- **Symptom (step 1):** The final image's container starts and dies immediately, or says no such file or directory even though the file is there
  **What to do:** That misleading message appears when the binary is dynamically linked and the final stage does not have the library it was linked against. The file it cannot find is not your binary, it is the dynamic loader. Compile with CGO_ENABLED=0 in the builder stage, which is what makes Go produce a static executable. Check it by extracting the binary with docker create and docker cp and looking at it with file: it has to say statically linked.

- **Symptom (step 1):** docker image ls and docker image inspect give very different numbers for the same image
  **What to do:** It is not an error, they are two different measurements. With the containerd snapshotter, docker image ls shows you a `DISK USAGE` column, which is what the uncompressed layers take on your disk, and a `CONTENT SIZE` column, which is the content-addressable content. The .Size field of docker image inspect corresponds to that second measurement. The check uses inspect on purpose, because it is the one that does not change depending on which other images share layers with yours.

- **Symptom (step 1):** The curl to the container does not answer and you published no port
  **What to do:** On Linux you can talk straight to the container's IP without publishing ports, which is why this step does not use -p: that way it does not step on any port belonging to another lab you have running. Get the IP with docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' and hit that IP on 8080. If you prefer publishing, publish on 127.0.0.1 and on a port nobody else is using, but check first with ss -ltn.

- **Symptom (step 2):** The curl to the registry does not return the Docker-Content-Digest header
  **What to do:** Check the Accept header first. The distribution API returns the manifest in whatever format you say you accept, and if you say none it can hand you an old format or a 404. Send the request with -I, which does `HEAD`, and with an Accept that includes application/vnd.oci.image.manifest.v1+json and application/vnd.docker.distribution.manifest.v2+json. And remember to strip the carriage return with tr -d '\r' before comparing, because HTTP headers end in `CRLF` and your digest ends up with invisible junk on the end.

- **Symptom (step 2):** The new Pods sit in ErrImagePull after you pinned the digest
  **What to do:** Check you did not change the repository name while pasting the digest. The name the cluster resolves is cks-p05-registry:5000, the registry container's name inside the docker network; 127.0.0.1:5065 is the name your machine resolves and it means nothing inside the node. The digest is the same down both roads, because it is the same registry and the same repository; the only thing that changes is the host you reach it through.

- **Symptom (step 2):** You want to keep the tag and the digest at the same time and do not know whether it counts
  **What to do:** It does count, and it is a valid form: repository:v1@sha256:... reads well for a human and resolves by digest for the kubelet, because when a digest is present the tag is decoration. The check accepts that form. What it does not accept is a reference with no digest, because there the tag stops being decoration and starts ruling again.

- **Symptom (step 3):** trivy takes forever the first time or fails downloading the database
  **What to do:** The first run downloads the vulnerability database and stores it in the cache directory. The setup already downloaded it to ~/cks-lab/p05/trivy-cache, so export TRIVY_CACHE_DIR pointing there before scanning and you will reuse it. If your network blocks the registry the database comes from, the scan cannot be done and Step 3 is not gradeable; say so instead of inventing the result.

- **Symptom (step 3):** trivy reports zero vulnerabilities in both images
  **What to do:** Check two things. First, that you did not pass a --severity filter that leaves out what you are looking for; start with no filter and filter afterwards. Second, that you are scanning the registry image and not a local name pointing at something else; scan 127.0.0.1:5065/tienda/proveedor-a:2026-08 as written. If both come out clean, the database changed and the setup would have told you so with `ERROR DE SUSTRATO: TRIVY-NO-SEPARA-LAS-CAJAS` before letting you start.

- **Symptom (step 3):** The Deployment is created but the Pods sit in ImagePullBackOff
  **What to do:** You probably used 127.0.0.1:5065 in the manifest. Your machine resolves that name, the node does not: inside the node 127.0.0.1 is the node itself. The name the cluster resolves is cks-p05-registry:5000, the registry container attached to the docker network named kind. Scan with the first and deploy with the second; it is the same registry through two doors.

- **Symptom (step 4):** cosign sign asks you for a password and you set none
  **What to do:** cosign's private key is stored encrypted and the binary asks for the passphrase on the console. Export an empty COSIGN_PASSWORD before generating the pair and before signing, and it will stop asking. If you generated the pair with a passphrase and no longer remember it, delete despacho.key and despacho.pub and generate them again: since you have signed nothing with that key yet, you lose nothing.

- **Symptom (step 4):** Kyverno rejects the signed image too, with a message about the transparency log
  **What to do:** Three things, worth checking in order. First, that the public key was pasted into the YAML with its indentation intact, including the `BEGIN PUBLIC KEY` and `END PUBLIC KEY` lines; one run-together line and the key stops being valid. Second, that the signature was made with --tlog-upload=false and that the policy therefore needs rekor.ignoreTlog set to true and ctlog.ignoreSCT set to true; without that Kyverno goes looking for a public entry that signature never had. Third, that Kyverno was installed with features.registryClient.allowInsecure set to true, because the lab registry speaks HTTP and not HTTPS; the setup already installs it that way.

- **Symptom (step 4):** You signed using the host name 127.0.0.1:5065 and worry the cluster sees it under a different name
  **What to do:** It is not a problem, and understanding why is worth half a chapter. The host is not part of the repository: cosign stores the signature inside the tienda/proveedor-b repository of that same registry, under a tag derived from the digest. Kyverno reaches that same repository by the name cks-p05-registry:5000 and finds the same signature. What does matter is the digest, and that one is identical down both roads.

## Going further

- Push Step 1's size limit until it hurts: try a final stage based on a distroless image instead of scratch, and compare not just the size but what is left inside by extracting the filesystem with docker create and docker export. Then scan all three images (the bloated one, yours and the distroless one) with the lab's trivy and write down how many operating-system vulnerabilities each one reports. Compare the bloated image's number with yours.
- Run the experiment Step 2 only describes: rebuild a different image, push it to the registry under the same tag tienda/pan:v1, and watch the registry digest change. Then delete a Pod from the digest-pinned Deployment and see that the replacement still brings the old content, the one you pinned. Repeat the experiment with a tag-based Deployment and see the difference with your own eyes. That is the whole chapter in two minutes.
- Generate a bill of materials (SBOM) for both candidate images with trivy in CycloneDX or SPDX format, save them, and then scan the SBOM instead of the image. Compare the result against the direct scan. A stored SBOM lets you ask again tomorrow whether the box you approved today is still clean, without needing the image to still exist, and that is the practical reason SBOMs exist.
- Break the seal on purpose, which is the best way to believe in it. Build a new image from the approved one, push it to the registry under a different tag but into the same repository, and try to create a Pod with it in el-deposito. It will be rejected even though it comes from the approved supplier and the approved repository, because its digest is different and that digest has no signature. Then sign it and try again. That shows you the unit being signed is not the supplier and not the repository: it is the exact content.

## References

- Docker documentation, Multi-stage builds. Documents the builder pattern and `COPY --from` used to leave the toolchain behind in Step 1. https://docs.docker.com/build/building/multi-stage/
- Kubernetes documentation, Images. Documents image references by tag and by digest, imagePullPolicy defaults and the imageID field the checks read. https://kubernetes.io/docs/concepts/containers/images/
- Trivy documentation, Container image scanning. Documents the scanners, severity filters and JSON report structure this lab's Step 3 grades against. https://trivy.dev/latest/docs/target/container_image/
- Sigstore documentation, Cosign signing overview. Documents key-pair generation and signing container images with self-managed keys, the exact flow of Step 4. https://docs.sigstore.dev/cosign/signing/overview/
- Kyverno documentation, Verifying image signatures. Documents the verifyImages rule, attestors, mutateDigest and the rekor and ctlog settings this lab needs for an offline signature. https://kyverno.io/docs/policy-types/cluster-policy/verify-images/
- kind documentation, Local registry. Documents running a local registry container alongside a kind cluster and the containerd certs.d configuration the setup writes. https://kind.sigs.k8s.io/docs/user/local-registry/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
