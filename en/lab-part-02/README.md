# Part II - Lab: a badge that loses its master key, a guard who walks the round carrying no keys at all, a gate that started asking for ID again, and the admission rulebook somebody had taken off the wall

- Time: 55 min
- Points: 40

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the command sequence that solves it lives in that step's cmd field, for you to reveal after trying it with your own hands. Step 1 hands you a ServiceAccount that somebody, to get through a Friday, tied to cluster-admin inside the namespace, and asks you to leave it with only the permissions the application uses; grading asks kubectl auth can-i from both sides, requires yes on what must be allowed and no on a long list of things that must not, and that is why putting cluster-admin back is not a shortcut but the fastest way to lose the step. Step 2 asks you to turn off automatic ServiceAccount token mounting for one account and Pod pair, and to prove it from inside the container: the token directory may not exist, the account must still be the same one, and the application must still be doing its work while it is graded. Step 3 goes down to the node: this cluster's kubelet was left answering credential-free requests on port 10250, and it falls to you to close it and prove it, measuring the kubelet's live configuration instead of trusting a file, with the node still Ready and the API server still able to talk to it. Step 4 closes with the control plane: somebody removed NodeRestriction from the kube-apiserver's admission plugin list, and you have to audit it, put it back and show that the plugin is enforcing something, not merely showing up in a flag.

## Prerequisites

- A Linux machine with kind, kubectl and docker on PATH, internet access, and at least 4 GB of free RAM. This lab creates its own kind cluster named cks-p02, with a single node, and deletes it at the end. Everything it does goes through a private kubeconfig at ~/cks-lab/p02/kubeconfig, passed with --kubeconfig on every single command: your usual kubeconfig is never touched, your current context never changes, and no other cluster of yours is affected. Do not run this lab against a production cluster, because Steps 3 and 4 modify the node's kubelet and kube-apiserver.
- Run and verified on 2026-10-11 on the test machine with kind v0.33.0, kubectl client v1.37.0 and Docker 29.9.0, node image kindest/node:v1.34.2 pinned by digest sha256:745f8ed46d8e99517774768227fd1a0af34a6bf395aef9c7ed98fbce0e263918 (the 1.34 line is the CKS curriculum this book accompanies), and the workload image busybox:1.37.0 pinned by digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Confirm your kind with kind version and your kubectl with kubectl version --client before you start, rather than taking this paragraph's word for it.
- The setup script does not just build the cluster: it runs four tests on it before letting you start, because the four steps assume behaviors a cluster can accept over the API and never enforce. It checks that RBAC denies what is not authorized, that the ServiceAccount token is mounted on its own when nobody forbids it, that the restricted label's denial comes from NodeRestriction and from no other control, and that this node's kubelet did authenticate before being broken and is open afterwards. If any of them fails, the setup prints a named error and stops, because a lab that grades a control nobody enforces is decoration.
- The setup deliberately leaves two hardening faults in this cluster's control plane, and applies them as base64 payloads so you cannot read the breakage in the script and go copy the answer. It is not cryptographic secrecy, it is a courtesy blindfold: if you want to, you decode them in ten seconds, and the answer key is in each step's cmd field. The point is that you audit the cluster in front of you, which is what you will be asked to do on exam day and at work.
- Having read Chapters 3 and 4. This lab does not re-explain what a Role is, how it differs from a ClusterRole, what a ServiceAccount is or what an admission plugin is; it makes you operate all four against a real cluster and grades them against its real state. Keep in mind that Steps 3 and 4 restart control plane components: if you have just touched the kubelet or the kube-apiserver, give the cluster half a minute before grading any step again.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 3: The guard's badge had keys to spare, and we are taking them off one by one (10 pts)

Chapter 3 told you this with the guard's badge: the ServiceAccount says who, the Role says what may be done, and the RoleBinding is the act of handing that permission to that badge. Here you get to live the ugly part, the one you meet on real clusters: arriving at a gatehouse where somebody already handed out the keys and nobody remembers why.

Here is the situation: the `porteria` namespace holds a RoleBinding called llave-maestra-del-celador, and its roleRef points at cluster-admin. That was not an attack, that was a Friday at six in the evening: the gatehouse application started failing with 403, somebody searched the internet, the first answer they found worked immediately, and there it stayed. The gatehouse uses two permissions and holds all of them.

The tool that will save your exam is kubectl auth can-i with --as. It lets you ask the API server, without deploying anything and without waiting for something to break, whether a specific identity can perform a specific action. Always use it from both sides: ask about what must be allowed and ask about what must not. A permission tested only from the positive side is not tested, it is assumed.

One detail is expensive on exam day: get, list and watch are three different verbs, and it is easy to merge them in your head because kubectl get uses them almost together. Asking for the whole collection is list. Staying on the line listening for changes is watch. If your application does not listen for changes, watch does not belong in the Role, and this step's grading will ask you about that very line.

Tying cluster-admin back on is not a quick fix, it is giving up on the whole model. A compromised container wearing that badge reads every Secret in the namespace on the first line of its script, and you found out three weeks later. If you are tempted to think this lab is exaggerating, look at the Secret's 403 from inside the Pod and think about how many containers at your job would make that same call and get a 200.

DELIVERABLE: the `celador-de-turno` ServiceAccount untouched, with cluster-admin nowhere near it, holding only get, list and watch on pods and get and list on configmaps inside the `porteria` namespace; the `garita` Pod still running with that badge on; and the file `~/cks-lab/p02/01-respuesta.txt`, exactly 5 lines:

```text
CUENTA_DE_LA_GARITA=<the name of the ServiceAccount the garita Pod declares>
PUEDE_LISTAR_PODS=<what kubectl auth can-i list pods answers for that badge in `porteria`>
PUEDE_BORRAR_PODS=<what kubectl auth can-i delete pods answers for that badge in `porteria`>
PUEDE_LEER_SECRETS=<what kubectl auth can-i get secrets answers for that badge in `porteria`>
CODIGO_EN_LOS_SECRETS=<the HTTP code the API server returns when the garita Pod asks for the clave-de-la-reja Secret with its token>
```

<details>
<summary>What you should see</summary>

The first command shows you the size of the problem in five lines: the RoleBinding's roleRef says kind ClusterRole and name cluster-admin, which means that inside this namespace that badge can do anything. When you delete it, kubectl answers `rolebinding.rbac.authorization.k8s.io "llave-maestra-del-celador" deleted from porteria namespace`. Then the new Role and RoleBinding are created without fuss, and the nine auth can-i questions answer, in order: yes for list pods, yes for watch pods, yes for get configmaps, no for watch configmaps, no for delete pods, no for get secrets, no for create pods, no for list pods in kube-system, and no for the wildcard question about everything everywhere. Look at the fourth line, the one easiest to miss: get and list on ConfigMaps yes, watch no, because watch is a separate verb and the application does not use it. From inside the garita Pod, the three calls to the API server with the projected token return HTTP/1.1 200 for the Pod list, HTTP/1.1 200 for the turnos-del-mes ConfigMap, and HTTP/1.1 403 for the clave-de-la-reja Secret. Each call is retried up to three times if the first try returns no code. That 403 is the one to look at slowly: it is not that the guard cannot find the gate's key, it is that the API server knows who is asking and tells them no.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 3: The guard walks the round without a single key in his pocket (10 pts)

Chapter 3 ended with the phrase that names half this lab: there are keys you never lend out. And in Kubernetes the key most often lent without anyone asking is the ServiceAccount token, because it mounts itself. You create a Pod, you write nothing about accounts or tokens, and inside the container a directory appears with a ca.crt, a namespace and a token that talks to the API server.

That mount was a convenience default from many years ago and today it is the first thing anyone who manages to run a command inside one of your containers goes looking for. They do not need to break anything: they read a file. If that account has permissions to spare, the whole complex is gone. It is common for an application never to talk to the API server at all: it serves a page, drains a queue or writes to a database.

That is why the night round's guard goes out with no keys. The field is called automountServiceAccountToken and it can be written in two places: on the ServiceAccount, where it sets the default for every Pod that uses it, and in the Pod spec, which overrides it. The practice asked for on exam day and in any serious review is to put it in both: the account closes by default and the Pod confirms it, so that if somebody edits the account tomorrow, the Pod does not open on its own.

There is an operational detail that tends to cost a first attempt: that Pod field cannot be changed hot. A Pod spec is almost entirely immutable, so no kubectl edit will help here; you have to delete the Pod and create it again with the field in place. In a Deployment you edit the template and the controller does the replacement for you, but the underlying mechanism is the same: a new Pod.

One shortcut does not work: changing the Pod's account so the directory disappears is not turning the mount off, it is changing identity. The default account mounts a token too, so it would not even work; and if it did, you would have cured the symptom while leaving the original account as open as it was. Taking the key away means taking the key away, not swapping guards.

DELIVERABLE: the `celador-sin-llaves` ServiceAccount with automountServiceAccountToken set to false, the `ronda-nocturna` Pod running with that same account and with automountServiceAccountToken set to false in its own spec, with no token directory inside the container, and with its `/tmp/ronda.log` still growing. Plus the file `~/cks-lab/p02/02-respuesta.txt`, exactly 4 lines:

```text
AUTOMOUNT_EN_LA_CUENTA=<the value of the automountServiceAccountToken field on the ServiceAccount>
AUTOMOUNT_EN_EL_POD=<the value of the same field in the Pod spec>
CARPETA_DEL_TOKEN=<write EXISTE or NO_EXISTE depending on what you find inside the container>
CUENTA_DE_LA_RONDA=<the name of the ServiceAccount the Pod declares>
```

<details>
<summary>What you should see</summary>

The first ls, run before touching anything, prints three names inside the token directory: ca.crt, namespace and token. Those three files showed up on their own, with nobody asking for them, and that is the point of this step. The grep on the ServiceAccount finds nothing, which is why the parenthesised line prints: when the automountServiceAccountToken field is not written, the effective value is to mount. After the patch and after recreating the Pod, the ls fails with ls: /var/run/secrets/kubernetes.io/serviceaccount: No such file or directory and behind it comes the line (no hay carpeta de token); the directory is not empty, it is absent. The jsonpath prints cuenta=celador-sin-llaves and automount_del_pod=false, which are the two things grading will read. And the two wc -l runs eight seconds apart return two different numbers, the second larger than the first (1 and 3 in the 2026-10-11 run), with the tail showing recent timestamps: the round is still working with no keys on it, which is the half of the step that is easy to forget.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 4: The complex's gate was opening for anybody who rang the bell (10 pts)

Chapter 4 told you about the complex's electric gate: the one that opens by itself, that everyone uses, and that nobody inspects until the day it opens when it should not. In a Kubernetes cluster that gate is called the kubelet and it answers on port 10250 of every node.

The kubelet is not an infrastructure detail: it is the one thing in the cluster that can run commands inside your containers, read any Pod's logs and tell whoever asks everything that is running on the machine. If that door answers without asking for ID, it does not matter how much RBAC you wrote above it: the attacker does not go through the API server at all, they talk straight to the node.

And there are two different controls here that are easy to confuse. The first is authentication: who you say you are. When anonymous access is enabled, anybody who rings the bell gets in under the name system:anonymous. The second is authorization: what you may do once inside. When the mode is AlwaysAllow, the kubelet says yes to everything without asking anyone. Webhook is the good mode, because the kubelet consults the API server with a SubjectAccessReview before every request. Both have to be right; fixing only one leaves half the hole open.

There is a third thing worth looking at right away because it comes up on exam day: the readOnlyPort, port 10255, which used to serve metrics and status with no authentication at all. On this node it ships turned off, and this step's probe confirms that rather than assuming it. That is the habit we want to leave you with: measure, do not assume.

There is a shortcut worth naming before it occurs to you: turning the kubelet off is not closing the gate, it is tearing the gate down. The probe does stop answering, yes, but the node goes NotReady and your Pods are left with nobody looking after them. Same with blocking the port at the firewall: it looks similar from outside and it is something else on the inside. Closing it properly means the kubelet keeps working, the API server keeps reaching it, and the stranger gets a 401 in the face.

DELIVERABLE: this node's kubelet with anonymous access disabled and the authorization mode set to Webhook, verified in the live configuration and not only in the file; the node still Ready; the `garita` and `ronda-nocturna` Pods still Running; and the file `~/cks-lab/p02/03-respuesta.txt`, exactly 4 lines:

```text
CODIGO_SIN_CREDENCIALES=<the HTTP code https://127.0.0.1:10250/pods returns from inside the node, with no credentials>
ANONIMO_HABILITADO=<the value of authentication.anonymous.enabled in the kubelet's live configuration>
MODO_DE_AUTORIZACION=<the value of authorization.mode in the kubelet's live configuration>
ARCHIVO_DE_CONFIGURACION=<the absolute path of the configuration file the kubelet process declares on its command line>
```

<details>
<summary>What you should see</summary>

The first line is the one that hurts: sin_credenciales=200. A request carrying no certificate and no token just pulled the node's Pod list out of the kubelet. Reading the live configuration confirms why: "anonymous":{"enabled":true} and "authorization":{"mode":"AlwaysAllow", which are the two halves of the problem, one letting people in without ID and another one then saying yes to everything. The third line tells you where the kubelet gets that configuration from, and on this node it prints --config=/var/lib/kubelet/config.yaml. After the fix and the restart, the node returns to Ready, both Pods return to Ready, and the same request prints sin_credenciales=401: the kubelet no longer answers anything to whoever does not identify themselves. The probe against the read-only port prints puerto_de_solo_lectura=000, which is not an HTTP code but curl's way of telling you nobody is listening there, and that is correct: on this node readOnlyPort ships turned off. The live configuration now says "anonymous":{"enabled":false} and "authorization":{"mode":"Webhook", and the exec into the garita Pod prints its message, which is the proof that you closed the gate to strangers and not to the API server. If the exec answers pod does not exist, it is not a failure: the kubelet has just restarted and has not re-synced its Pod list yet. In the 2026-10-11 run the first attempt gave that error and the second printed the message; the loop in the command already retries.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 4: The admission rulebook had been taken off the office wall (10 pts)

Chapter 4 told you the complex's management keeps a rulebook hanging on the wall, and that a rulebook is worth nothing filed in a drawer. In Kubernetes that rulebook is the kube-apiserver's admission plugins: code that sits between authentication and the write to etcd, and that can reject, change or wave through every object entering the cluster.

The enabled plugin list is declared in a kube-apiserver command line flag, --enable-admission-plugins, and on a kubeadm-built cluster that command lives in a static Pod file inside the node. Which means auditing this is not a kubectl get: you have to go look at the manifest and, better still, at the command line of the running process, because the file and the process can disagree.

The plugin that falls to you today is NodeRestriction, and its job is to limit what a kubelet may do to its own Node object. Without it, a compromised node can edit labels onto itself to attract workloads that were never meant for it, among other more entertaining things. With it, there is a set of labels the node simply cannot touch, and in this lab you are going to verify that with labels carrying the node-restriction.kubernetes.io/ prefix, which exist precisely for this: to label nodes in a way the node itself cannot forge.

The way to verify it is the part worth learning. It is not about reading the flag and believing it: it is about impersonating the node's kubelet identity, with --as and --as-group, attempting the forbidden action, and seeing the denial with your own eyes. That technique works for any admission control you want to audit, not only this one.

This step hides a shortcut of a different kind, the cleanest in the lab: you could get the label rejected without turning the plugin on, simply by breaking the node's permissions. The denial would look similar and you would call it done. That is why grading, after demanding the denial, applies an ordinary label with the same identity and demands that this one go through. If both fail, you did not harden the cluster: you broke it.

DELIVERABLE: this node's kube-apiserver running with NodeRestriction in the --enable-admission-plugins list, the same plugin present in the static Pod manifest on disk, the cluster healthy (node Ready, /healthz answering ok, both gatehouse Pods Running), and the file `~/cks-lab/p02/04-respuesta.txt`, exactly 4 lines:

```text
BANDERA_DE_ADMISION=<the exact name of the kube-apiserver flag that lists the enabled admission plugins, with its two dashes>
PLUGINS_HABILITADOS=<the live value of that flag, verbatim, without the flag name>
ARCHIVO_DEL_MANIFIESTO=<the absolute path of the kube-apiserver static Pod manifest inside the node>
RESPUESTA_A_LA_ETIQUETA=<the word in parentheses in the API server's error when the node tries to put a node-restriction.kubernetes.io/ label on itself>
```

<details>
<summary>What you should see</summary>

The first line is the audit finding: the live flag says "--enable-admission-plugins=LimitRanger". It is not empty, and that is why it is so easy to skim past: there is a plugin list, it looks populated, and what is missing is precisely the one that matters. staticPodPath comes out as "staticPodPath":"/etc/kubernetes/manifests", which is where this node's kubelet looks for static manifests, and the grep confirms the same flag on line 19 of the kube-apiserver.yaml file. The test before the fix is conclusive: the first attempt to put a label with the node-restriction.kubernetes.io/ prefix on the node while impersonating the kubelet itself prints node/cks-p02-control-plane labeled, which means it went through. After correcting the manifest, the kube-apiserver restarts on its own (the kubelet watches that directory) and within about twenty seconds the live flag prints bandera viva: --enable-admission-plugins=NodeRestriction, with /healthz answering ok. And the same label attempt now answers Error from server (Forbidden): nodes "cks-p02-control-plane" is forbidden: is not allowed to modify labels: node-restriction.kubernetes.io/prueba, while the ordinary label ejemplo.com/prueba does apply and returns node/cks-p02-control-plane labeled. That contrast is the whole step: the same identity, two labels, one denied and the other allowed, and the difference was made by the admission plugin.

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

- **Symptom (step 1):** auth can-i answers no for list pods even though the Role and the RoleBinding already exist
  **What to do:** The most common cause is that the RoleBinding points at the wrong subject. A ServiceAccount subject needs its namespace as well as its name, and if you leave the namespace out the binding ends up pointing at an account that does not exist, without raising any error. Look at the real subject with `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get rolebinding el-celador-solo-mira -o yaml` and confirm it says kind ServiceAccount, name celador-de-turno and namespace `porteria`. Another possible cause is a roleRef pointing at a ClusterRole when you created a Role, or the other way round: roleRef is immutable, so if it is wrong you have to delete the RoleBinding and create it again. And check that you are asking with the identity's full name, `system:serviceaccount:porteria:celador-de-turno`, because --as=celador-de-turno asks about a user that does not exist.

- **Symptom (step 1):** The auth can-i questions look right but the garita Pod still gets a 403 when listing Pods
  **What to do:** There are two causes and it is worth ruling them out in order. The first is that the Pod is not using the badge you fixed: confirm with `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get pod garita -o jsonpath='{.spec.serviceAccountName}'` that it says celador-de-turno and not default, because the field cannot be changed on a live Pod and you have to recreate it. The second is that the token mounted in the container predates your change; projected tokens refresh themselves, but if you have just recreated objects, re-read the token file inside the container instead of reusing a stale variable in your shell. To see who the API server believes is asking, use `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig auth whoami --as=system:serviceaccount:porteria:celador-de-turno`.

- **Symptom (step 2):** kubectl edit on the Pod answers that the automountServiceAccountToken field cannot be changed
  **What to do:** It is not your mistake: a Pod spec is immutable except for a handful of fields (the container image, activeDeadlineSeconds and tolerations, per the API documentation). automountServiceAccountToken is not on that list, so the only way out is to delete the Pod and create it again with the field in place. Use the manifest the setup left you at ~/cks-lab/p02/ronda-nocturna.yaml, add the line automountServiceAccountToken: false at the same level as serviceAccountName, delete the Pod with `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria delete pod ronda-nocturna --now` and apply it again. If this were a Deployment you would edit the template and the controller would do the replacement, but underneath it would also be a new Pod.

- **Symptom (step 2):** The token directory is gone but the check still fails
  **What to do:** Go back over the three requirements that are not the directory. First, the field on the ServiceAccount: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get sa celador-sin-llaves -o jsonpath='{.automountServiceAccountToken}'` must print false, and if it prints empty you only set it on the Pod. Second, the Pod's account: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get pod ronda-nocturna -o jsonpath='{.spec.serviceAccountName}'` must say celador-sin-llaves. Third, and this one is easy to forget, the log: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log'` must return a number that grows if you ask for it twice a few seconds apart. If you changed the command to a sleep when you recreated the Pod, the round stopped working and the step fails even though the token is gone.

- **Symptom (step 3):** You edited /var/lib/kubelet/config.yaml but /configz still shows the old values
  **What to do:** The kubelet reads that file at startup, not hot, so the file and the process can be saying different things and that difference is what this step measures. Restart the service with docker exec cks-p02-control-plane systemctl restart kubelet and wait for the node to come back Ready with kubectl --kubeconfig ~/cks-lab/p02/kubeconfig wait --for=condition=Ready node/cks-p02-control-plane --timeout=180s. If the node does not come back after the restart it is most likely an indentation mistake in the YAML you just edited: look at it with docker exec cks-p02-control-plane journalctl -u kubelet -n 40 --no-pager, which will tell you which line it choked on.

- **Symptom (step 3):** The probe returns 403 instead of 401 and the check fails
  **What to do:** That 403 is telling you something precise: the kubelet did let the anonymous request in, and what stopped it was authorization, not authentication. In other words you fixed authorization.mode but left authentication.anonymous.enabled at true. Confirm it by reading the live configuration with kubectl --kubeconfig ~/cks-lab/p02/kubeconfig get --raw /api/v1/nodes/cks-p02-control-plane/proxy/configz | tr ',' '\n' | grep -i anonymous, set that field to false in the kubelet's configuration file, restart the service and probe again. It is worth comparing the two codes calmly once, because telling 401 from 403 in a probe is one of the readings that most quickly tells you which control is failing.

- **Symptom (step 4):** You edited the manifest but the kube-apiserver's live flag still shows the old value
  **What to do:** A static Pod is not applied with kubectl: it is watched by the kubelet, which looks at the directory declared in staticPodPath and recreates the container when the file changes. That cycle takes on the order of twenty seconds on this cluster, so the first thing to do is wait. If the flag has not changed after a minute, check whether the container is restarting in a loop with docker exec cks-p02-control-plane crictl ps -a | grep apiserver and read the reason with docker exec cks-p02-control-plane crictl logs $(docker exec cks-p02-control-plane crictl ps -a -q --name kube-apiserver | head -1). A misspelled plugin name stops the kube-apiserver from starting, and then you have no API server left to ask why it did not start, which is the reason this file gets edited slowly.

- **Symptom (step 4):** kubectl stops answering entirely after touching the kube-apiserver manifest
  **What to do:** This is the scenario this step wants you to live through once on a disposable cluster and never again on a real one. The API server did not start, and since kubectl talks to the API server, you are out of tools. The way out is always through the node, not through kubectl: get in with docker exec -it cks-p02-control-plane bash, look at the file with less /etc/kubernetes/manifests/kube-apiserver.yaml and fix what you typed wrong. If you cannot spot the error by eye, check the container logs with crictl logs, and if you simply want to go back to the starting point, the lab is disposable: delete the cluster with kind delete cluster --name cks-p02 and run the setup again. The habit worth taking away is copying the manifest before touching it.

## Going further

- Go back to Step 1 and replace the namespaced Role with a ClusterRole carrying the same rules, tied with a RoleBinding inside `porteria`. Run the check again: it passes, because the end state is what is graded. Now swap that RoleBinding for a ClusterRoleBinding and run it again: it fails, and not because the exercise is being fussy but because the same ClusterRole tied the other way just opened kube-system to the guard. That pair of experiments burns in the difference between the role and the binding, which is one of the central distinctions in RBAC.
- Create a third Pod in the `porteria` namespace that uses the celador-sin-llaves ServiceAccount and says nothing about automountServiceAccountToken in its own spec. Go in and see whether it has a token directory. Then set the field to true on that Pod only, recreate it and look again. With those two attempts you have just verified the precedence rule in practice: the Pod spec overrides the account's default, in both directions, and that is why the advice to write it in both places is not redundancy but closure.
- With the kubelet already hardened, try Step 3's same probe but authenticating properly: take the client certificate the kube-apiserver uses to talk to the kubelet, which on this node lives under /etc/kubernetes/pki, and repeat the call to https://127.0.0.1:10250/pods passing it with --cert and --key. Now it will answer with the Pod list. That exercise shows you that hardening the kubelet was not closing the port, it was demanding ID from whoever rings the bell, and along the way it makes clear why that control plane certificate deserves the same care as a key to the safe.
- Add a second admission plugin from the official list to the kube-apiserver alongside NodeRestriction, for example NamespaceLifecycle, separated by a comma, and confirm that Step 4 still passes. Then attempt an impossible combination by putting the same name in --enable-admission-plugins and in --disable-admission-plugins at once, and observe what the kube-apiserver does at startup. Run that second experiment knowing you will have to go in through the node to fix it, which is the practice we want you to have before it happens on a cluster you care about.

## References

- Kubernetes Project, Using RBAC Authorization. Primary source for Role, ClusterRole, RoleBinding and ClusterRoleBinding, for the ServiceAccount subject needing a namespace, for the immutability of roleRef, and for the distinction between the get, list and watch verbs that Step 1 grades on both sides. https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Kubernetes Project, Authorization Overview. Documents kubectl auth can-i, including the --as impersonation flag, the --subresource flag and the --all-namespaces form, which are the tools Step 1 is graded with on both the allowed and the forbidden side. https://kubernetes.io/docs/reference/access-authn-authz/authorization/
- Kubernetes Project, Role Based Access Control Good Practices. The project's own least privilege guidance, including why cluster-admin should not be handed to workloads and why ServiceAccount token access is worth restricting, which is the reasoning behind Steps 1 and 2. https://kubernetes.io/docs/concepts/security/rbac-good-practices/
- Kubernetes Project, Configure Service Accounts for Pods. Primary source for serviceAccountName, for automountServiceAccountToken on both the ServiceAccount and the Pod spec and for the precedence between them, and for the projected token, ca.crt and namespace files under /var/run/secrets/kubernetes.io/serviceaccount that Steps 1 and 2 read from inside the container. https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- Kubernetes Project, Service Accounts. Explains what a ServiceAccount is, how bound tokens are issued and projected into Pods, and why a workload that never calls the API server should not carry one, which is the argument Step 2 turns into a graded end state. https://kubernetes.io/docs/concepts/security/service-accounts/
- Kubernetes Project, Kubelet authentication/authorization. Primary source for anonymous requests to the kubelet being given the username system:anonymous, for disabling them so unauthenticated requests receive 401 Unauthorized, and for the AlwaysAllow and Webhook authorization modes and the SubjectAccessReview the kubelet issues in Webhook mode. Step 3 measures exactly these two settings. https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/
- Kubernetes Project, Kubelet Configuration (v1beta1) API reference. Primary source for the KubeletConfiguration file fields this lab edits and grades: authentication.anonymous.enabled, authorization.mode, readOnlyPort and staticPodPath, which are the config-file equivalents of the kubelet command line flags. https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
- Kubernetes Project, Set Kubelet Parameters Via A Configuration File. Documents the --config flag, the fact that the kubelet reads its configuration file at startup rather than hot, and how to inspect the configuration actually in use, which is why Step 3 grades /configz and not the file alone. https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/
- Kubernetes Project, Admission Control in Kubernetes. Primary source for the --enable-admission-plugins and --disable-admission-plugins flags, for the list of plugins including NodeRestriction, and for what NodeRestriction restricts on a kubelet's own Node object. Step 4 audits and restores exactly this flag. https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/
- Kubernetes Project, Using Node Authorization. Documents the Node authorizer, the system:nodes group and system:node:<name> identity that Step 4 impersonates, and states that the NodeRestriction admission plugin is what limits a kubelet to modifying its own node. https://kubernetes.io/docs/reference/access-authn-authz/node/
- Kubernetes Project, Create static Pods. Primary source for the staticPodPath directory the kubelet watches and for the fact that editing a manifest there makes the kubelet recreate the Pod, which is the mechanism Step 4 depends on to restart the kube-apiserver. https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
- kubernetes-sigs/kind, release v0.33.0. The kind release used to build this lab's cluster; documents the --config, --image and --kubeconfig flags the setup uses to build an isolated cluster without touching any other kubeconfig. https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0
- kind Project, Quick Start. Documents kind create cluster and kind delete cluster with the --name flag and the kubeconfig handling that keeps this lab's cluster isolated in a private file. https://kind.sigs.k8s.io/docs/user/quick-start/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
