# Part VI - Lab: the gatehouse logbook nobody read, the film of who came in at dawn, the camera that only records when somebody is sitting down, and the shop that refuses to be remodelled mid-shift

- Time: 60 min
- Points: 40

## Objective

This is an Exam-Style lab: each step states only the objective, and that step's full command sequence lives in its cmd field, for you to reveal after you have tried to solve it with your own hands. Step 2 is also pure diagnostics: the cluster arrives with an incident that has already happened, applied by the setup from a base64-encoded payload. That is not cryptography and does not pretend to be: it is a courtesy blindfold, so you do not read in the same script what you are supposed to reconstruct from the log. The incident is the same on every run, and the full answer key sits in Step 2's cmd field. The cluster is born with API server auditing switched on from the first minute, with its own policy mounted through kubeadm patches, because a logbook opened after the burglary is worth nothing. Step 1 asks you to perform an action that gets written down, find it in the log, and answer who did it, with which verb, on which resource and at which level it was recorded. Step 2 hands you a completed theft and a single source of truth: you reconstruct who came in, at what moment the door was opened for them and what they took, and then contain the damage without destroying the evidence. Step 3 switches on the cameras, with Falco reading system calls through modern eBPF, and asks you to trigger the canonical alert for a shell inside a container; the rule does not fire on just any exec, and working out why is the job. Step 4 puts a padlock on the shop: converting a Deployment to a read-only root filesystem without the application stopping its sales, and confirming that coming in through the service door leaves a trace in the same logbook as Step 1. No check settles for what you wrote down: every one re-queries the cluster at grading time, those of Steps 3 and 4 step into a container and test it themselves, and all of them demand that the control that was in the way is still in place. Switching auditing off, silencing the Falco rule, deleting the compromised account or removing the padlock so the symptom goes quiet are the four shortcuts this lab punishes.

## Prerequisites

- A disposable Linux x86_64 machine with kind, kubectl, docker (reachable without sudo), base64, jq and script (the util-linux one, the tool that allocates a terminal) on PATH, and at least 6 GB of free RAM. Confirm each tool with its own --version before you start; do not take this prose on trust. Run on 2026-10-11 with kind v0.33.0, kubectl client v1.37.0 and Docker 29.9.0.
- Isolation (not optional). The lab creates its own single-node kind cluster called cks-p06 and writes its kubeconfig into a private file, ~/cks-lab/p06/kubeconfig, from the very first command. Every kubectl command in this lab carries --kubeconfig pointing at that file, and you must do the same. Never rely on the current context of your ~/.kube/config: if you have another cluster open, a kubectl delete without --kubeconfig lands on that one and not on this one. The lab touches no other cluster, context or container on your machine.
- Images pinned by digest (digests verified on 2026-08-21 and used unchanged in the 2026-10-11 run). The cluster node: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, the image kind v0.32.0 declares as its own (the 2026-10-11 run used kind v0.33.0 with this same pinned image). The cameras: falcosecurity/falco@sha256:d0cfe422d6ac0e0f20857798f46c7d7273210e1b064b22821e4e6e7f843cde6b, which is Falco 0.44.1 with the modern_ebpf engine already inside the binary. The applications: busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 (BusyBox v1.37.0), which ships the httpd server the till serves with. The mandadero Pod, the telephone the Service is called from: curlimages/curl@sha256:d94d07ba9e7d6de898b6d96c1a072f6f8266c687af78a74f380087a0addf5d17. A tag is mutable and a digest is not: the chapters teach you to look up the current version, and the lab pins it so the exercise is reproducible.
- The logbook and the cameras are read through two shortcuts that setup writes for you. The API server's audit log lives inside the node, at /var/log/kubernetes/audit/audit.log, and belongs to root, so it is read by stepping into the node container. Setup leaves you `~/cks-lab/p06/bin/minuta`, which does just that, and `~/cks-lab/p06/bin/camaras`, which does the same with Falco's alert file at /var/log/falco/events.txt. Both print one JSON line per event, so read them with jq and not by eye.
- Internet egress during setup, to pull the four pinned images. Grading needs no internet, only the live cluster and the node running: the checks query the API server, read the log and the alert file inside the node, and call the Service from inside the cluster itself.
- Setup takes about a minute and hands the cluster back with an incident that has already happened, on purpose. Before handing it over it runs two probes and stops with a named error if either fails: one on the logbook (the API server is writing the log and the policy puts Secrets at RequestResponse level: `ERROR SONDA-MINUTA-MUDA` and `ERROR SONDA-NIVEL-SECRETOS`) and one on the cameras (Falco with modern_ebpf sees a shell with a terminal inside a container on this node: `ERROR SONDA-CAMARAS-CIEGAS`). If your kernel will not run the modern eBPF engine, setup stops there instead of handing you a Step 3 with no floor under it. To start over, run the full teardown and then setup again: the incident is applied during setup, not step by step. Teardown deletes only the cks-p06 cluster and the ~/cks-lab/p06 directory.
- Falco runs privileged and with hostPID, and that is why it sees the system calls of the whole kernel of your machine, not only this cluster's. If you have other containers or clusters running, alerts that are not yours will show up: that is not a bug, it is how a runtime agent on a real node works. That is why every Step 3 check binds the alert to the container id of the exercise's Pod, and not to the rule name alone.
- Having read Chapters 13, 14 and 15. This lab does not re-explain what an audit policy is, how the Metadata and RequestResponse levels differ, how a runtime detector works or why an immutable container is harder to break into; it makes you operate all three against a real cluster that has already been robbed.
- One warning about Step 2, worth reading before you start: that step's evidence lives in the audit log, and the log can be truncated. If you clean the file up so it looks tidy, you lose the incident and will have to run teardown and setup again. Read before you sweep.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 14: The gatehouse logbook nobody read (10 pts)

Here's what's actually going on: the gated community on the corner bought a beautiful hardcover logbook and put it in the gatehouse the day they hired a new guard. It has been there three years. Nobody has written a line in it. When the bicycle from 402 went missing they went to look at the book and it was blank, and the administrator said the line that gets said in these cases: "nobody knew we were supposed to write things down".

The problem was not the thief; it was that the logbook was opened after the burglary. Chapter 14 put it in these words: an audit log is not useful for what is about to happen, it is useful for what already happened, and that is why it has to be switched on beforehand. In Kubernetes that means the API server starts with an audit policy mounted from the first minute, and in this lab the cluster was born that way: the policy is mounted as a file inside the node and the API server receives it through kubeadm patches, with --audit-policy-file and --audit-log-path.

Now, a logbook does not write everything down the same way. This cluster's policy has a rule recording Secrets at RequestResponse level, the most detailed of the four, and a final rule leaving everything else at Metadata. That difference is not a configuration detail: it separates "somebody touched the safe" from "somebody touched the safe and this is what they took out". Step 2 lives entirely off that difference, and this is where you first see it.

Your job in this step is easy to say and harder to do without reading: perform an action that gets written down, go to the log, find it, and answer with the data the event itself carries. Careful with the group: do not invent it, read it off the event. On this cluster the admin certificate does not come in the group you are imagining.

And the warning, which in this step is the easiest one to run into: the log grows quickly. The temptation to truncate it "so I can work comfortably" exists, and it is the first thing somebody who got in where they should not have would do. The check creates a fresh stamp after grading your lines and demands to see it appear in the log, so a log that is switched off or swept clean fails the step even if your answer file is perfect.

DELIVERABLE: the `libro-de-minuta` Secret created in the `la-porteria` namespace with the `clave` key, and the file `~/cks-lab/p06/01-respuesta.txt`, exactly 5 lines:

```text
USUARIO=<the username the log recorded for that creation>
GRUPO=<that user's group that appears in the event and that is not system:authenticated>
VERBO=<the verb that was recorded>
RECURSO=<the resource that was recorded, plural, as the log writes it>
NIVEL=<the audit level that event was written at>
```

<details>
<summary>What you should see</summary>

The Secret is created without fuss and three seconds later it is already written down. The event the log returns is a JSON object with kind Event and apiVersion audit.k8s.io/v1; it carries level RequestResponse, stage ResponseComplete, verb create, the objectRef with resource secrets, namespace la-porteria and name libro-de-minuta, and the user block with username kubernetes-admin and groups kubeadm:cluster-admins and system:authenticated. It also carries two fields that make the full read worth it: requestObject and responseObject, with the Secret's body, that is, the key you just stored, in base64, written forever into a text file. The policy the API server has mounted explains why: there is a rule with level RequestResponse for Secrets, and a final rule with level Metadata for everything else. The flags the log was opened with are --audit-policy-file=/etc/kubernetes/audit/policy.yaml and --audit-log-path=/var/log/kubernetes/audit/audit.log, plus the three rotation ones.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 14: The film of who came in at dawn (10 pts)

The safe combination went missing from the community's storeroom, and the administrator wants to know who did it. There are no witnesses, no cameras on that corner and the guard on duty swears he saw nobody. The only thing there is is the logbook, which on this cluster has been switched on since the first minute.

You are not going to ask anybody. In a serious investigation testimony is checked against the record, not the other way round, and Chapter 14 built the film in that order: first who asked for what, then with what result, and only at the end who that identity was. The audit log gives you all three in the same file, and what you have to learn here is to sort them by time and read them as a sequence, not as loose events.

One detail is worth the whole step, and it is hidden in a response code. The account that took the secret tried before and could not. That first failed attempt is the most useful part of the whole film, because it tells you two things: the account already existed and was probing, and something changed between that moment and the next. Look for what changed in the middle. It is written down, by name, between the two attempts.

There is a second, more uncomfortable lesson. Because this cluster's policy records Secrets at RequestResponse level, the successful attempt's event does not only say "it read the safe": it carries inside what the safe contained. The log you use to investigate is also a text file with secrets in it, in base64, which is to say in the clear. That is not a defect of this lab, it is the real consequence of that level, and it is why containment in this step does not end with revoking a permission.

Then comes the temptation, which in this step is dressed up as diligence: deleting the compromised account. It feels responsible and looks clean, but doing it destroys the only identity that ties the film together. What has to go is the permission, not the subject. The check demands the account is still there, that it can no longer read Secrets, that the namespace's other account keeps working normally, and that the secret's value is no longer the one written into the log.

DELIVERABLE: the `la-bodega` namespace contained, meaning the compromised account still present but unable to read Secrets, the other account working as before and the `la-caja-fuerte` Secret carrying a new value; plus the file `~/cks-lab/p06/02-respuesta.txt`, exactly 5 lines:

```text
CUENTA=<the full username, as the log writes it, of the identity that read the Secret>
SECRETO=<the name of the Secret that was taken>
CODIGO_PRIMER_INTENTO=<the response code of that account's first attempt on that Secret>
ROLEBINDING=<the name of the RoleBinding created between the first attempt and the second>
VALOR_FILTRADO=<the value of the Secret's clave key, already decoded, as it ended up in the log>
```

<details>
<summary>What you should see</summary>

The film of the la-bodega namespace comes out sorted by time and reads itself. First kubernetes-admin creates the la-caja-fuerte Secret (RequestResponse level, code 201), the inventario ConfigMap, the auxiliar-de-dia account, a ConfigMaps-only Role and its turno-de-dia RoleBinding. Then it requests a token for auxiliar-de-dia (create serviceaccounts with subresource token) and that account reads the ConfigMap: 200, all normal, that is the day shift doing its job. Then the auxiliar-de-turno account shows up: a token is issued for it, it tries to list Pods and gets a 403, and it tries to read the la-caja-fuerte Secret and gets a 403 too. Less than a tenth of a second later, kubernetes-admin creates the llaves-de-la-caja Role and the prestamo-de-llaves RoleBinding, and about three seconds after that the same get on the same Secret by the same account appears, now with code 200 (2026-10-11 run). That 403 then 200 pair with a RoleBinding in the middle is the incident. And since Secrets are recorded at RequestResponse, the 200 event carries responseObject.data.clave in base64: decoding it gives combinacion-7431-de-la-caja-fuerte, which is what was taken. After containment, kubectl auth can-i answers no for that account and the Secret ends up with a different value.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 13: The camera that only records when somebody is sitting down (10 pts)

The community finally installed cameras, and the first month was wonderful: the parking problems stopped. The second month the complaints started, because the basement camera had recorded nothing the night somebody got into the storage room. The technician came, checked it, and said the most honest sentence in the whole affair: "that camera only records when it detects somebody sitting at the guard post".

Something similar happens in this step, on purpose. Falco is running, it is watching system calls through modern eBPF, and the canonical rule you care about is called Terminal shell in container. You will step into a container with kubectl exec, run something, and the alert will not come out. The Pod is fine, Falco is fine, the rule is in place. And it does not ring.

The camera is not broken: the rule's condition asks for something your exec is not giving it. Chapter 13 insisted on this: a detection rule is an expression, and an expression is not guessed, it is read. Falco ships its rules in a text file inside its own container, and that condition has five terms joined by and. Four are satisfied by any exec. The fifth one keeps it quiet.

Your job is to read the condition, work out which of the five terms is missing, supply it, and then find the alert and tie it to the right Pod. Tying it is not optional: Falco runs privileged and with hostPID, meaning it sees the whole machine's system calls, including containers that have nothing to do with this lab. Settling for "an alert from that rule came out" proves nothing. You have to get down to the container id and confirm it is the exercise Pod's.

And the warning, which in security is the most expensive one: a rule that annoys people can be switched off. You set enabled false in a rules.d file and the noise is over. This step's check fires a fresh alert of its own in another Pod and demands to see it arrive, precisely so that switching the rule off does not look like solving the exercise.

DELIVERABLE: the alert triggered on the `porteria` Pod in the `la-celaduria` namespace, with the Falco DaemonSet still switched on and the rule still active; plus the file `~/cks-lab/p06/03-respuesta.txt`, exactly 4 lines:

```text
REGLA=<the name of the rule that fired, as Falco writes it>
PRIORIDAD=<that alert's priority, as Falco writes it>
CAMPO_QUE_EXIGE_TERMINAL=<the field in the rule's condition that a normal exec does not satisfy, written as it appears in the condition, without the operator or the value>
CONTENEDOR=<the twelve-character container id the alert carries, without the containerd:// prefix>
```

<details>
<summary>What you should see</summary>

The falco DaemonSet shows 1 desired, 1 ready, and the first lines of its log say Falco version: 0.44.1 and list the configuration files it validated. The rule, read in /etc/falco/falco_rules.yaml, has a five-term condition joined by and (spawned_process, container, shell_procs, proc.tty != 0 and container_entrypoint), plus an exclusion for user-defined exceptions. The first exec, the normal one, produces no new alert: the counter does not move (in the 2026-10-11 run it read 1, the alert from the setup probe), and that silence is the diagnosis. The second exec, the one that asks for a terminal, does fire, and the alert comes out with rule Terminal shell in container, priority Notice, the output_fields["container.id"] field carrying twelve hexadecimal characters and proc.cmdline carrying the command you ran. That twelve-character id is the prefix of the containerID kubectl reports for the `porteria` Pod, which comes with the containerd:// prefix in front. It is worth noticing that the rule's own description recommends correlating it with the exec audit records, which is what you did in Step 1 and will do again in Step 4.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 15: The shop that refuses to be remodelled mid-shift (10 pts)

The shop on the corner changes shape every fortnight. One month they knock a wall down, the next they open a window onto the alley, and the owner tells it proudly as though it were dynamism. In the end they were robbed through the window opened "to let more light in", and the guard never noticed because he had spent three months watching workmen come and go with tools.

The problem was not the window; it was that the shop could be remodelled mid-shift. Chapter 15 put it this way: a container that can be modified while it runs is a container where somebody can leave something behind, and the answer is `readOnlyRootFilesystem`. With that, the container's root filesystem stops accepting writes, and everything an attacker wants to plant falls out of their hands.

The hard part is elsewhere, and it is why this step exists. Setting the padlock is one line. Keeping the business selling with the padlock on is the real work. This lab's `caja-registradora` writes in two places when it starts, and with a read-only root it dies on the first attempt. The solution is not to remove the padlock nor to complicate the image: it is to mount `emptyDir` right where the application needs to write, and nowhere else. Minimum writable surface. A drawer to work in, not a warehouse.

There are two shortcuts, both comfortable. The first is mounting a drawer on `/tmp` "just in case": that hands the attacker back the directory where downloads usually get dropped. The check tests `/tmp` by hand and demands it still refuses writes. The second is getting the space through a `hostPath`: that does not make the container immutable, it opens a door to the node, and the check counts the `hostPath` volumes and demands zero.

One last thing, which ties this step back to Step 1. You will step into the container with `kubectl exec` to test the padlock. That entry is written down in the same gatehouse logbook, with the resource, the subresource, the verb, the level and, on top of that, the command you ran inside. The Falco rule's description in Step 3 recommends it: when the camera shows you a shell inside a container, the logbook tells you which identity opened it. Camera and logbook do not compete, they complete each other.

DELIVERABLE: the `caja-registradora` Deployment in the `el-local` namespace running with `readOnlyRootFilesystem` set to true, with `emptyDir` drawers only where the application needs them, serving 200 through its Service; plus the file `~/cks-lab/p06/04-respuesta.txt`, exactly 5 lines:

```text
RECURSO=<the resource the log records for a kubectl exec>
SUBRECURSO=<the subresource the log records for a kubectl exec>
VERBO=<the verb your log recorded for that exec>
NIVEL=<that event's audit level>
ETAPAS=<the two stages that same exec left recorded, in chronological order, separated by a comma and no spaces>
```

<details>
<summary>What you should see</summary>

Before the padlock the container writes wherever it likes: /www/index.html and /var/log/local/ventas.log exist and its own startup command created them. After the patch the rollout finishes and the new Pod comes up 1/1, but only because both scratch drawers are in place: if you set readOnlyRootFilesystem without mounting anything, the container dies on the first mkdir with Read-only file system and the Deployment spins forever. With the drawers in place, the test from inside comes out like this: touch /www/prueba works, touch /tmp/prueba answers touch: /tmp/prueba: Read-only file system, touch /prueba answers the same, and the sales file keeps the shift-opening line. The call to the Service from the mandadero Pod returns 200. And the log carries, for every kubectl exec you ran, two events with the same requestReceivedTimestamp: one at stage ResponseStarted and one at ResponseComplete, both with resource pods, subresource exec, level Metadata and the Pod name. The verb depends on the transport your kubectl uses: with kubectl client v1.37.0 (2026-10-11 run), which negotiates WebSocket, it is recorded as get. And the requestURI carries the full command you ran, URL-encoding and all, so the log does not only say that you came in, it says what you did inside.

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

- **Symptom (step 1):** The minuta command answers 'Error: No such container' or prints nothing
  **What to do:** The log lives inside the cluster node, not on your disk, because the API server runs there and the file belongs to root. The `~/cks-lab/p06/bin/minuta` shortcut steps into the cks-p06-control-plane container with docker exec and cats the file. If the container does not exist, the cluster is gone: run teardown and setup again. If it exists and the file is empty, the API server started without the audit flag, which setup would have stopped with `ERROR SONDA-MINUTA-MUDA`; most likely somebody truncated the file afterwards.

- **Symptom (step 1):** I wrote `GRUPO=system:masters` because that is how the examples show it and the check rejects it
  **What to do:** That is the point of the step. system:masters is the break-glass certificate's group, and kubeadm stopped putting it on the admin kubeconfig you use daily years ago: it gives it its own group, tied to a ClusterRoleBinding with the cluster-admin ClusterRole. The log tells you in the event's user.groups field and, in its annotations field, writes down by name which ClusterRoleBinding authorized the request. Read it off the event, not off your memory.

- **Symptom (step 2):** I revoked the permission and kubectl auth can-i still answers yes
  **What to do:** A permission in RBAC is two objects: the Role, which says what can be done, and the RoleBinding, which says by whom. Deleting either one is enough to cut the access, but only if you deleted the one that ties that account. Confirm with kubectl -n la-bodega get rolebindings -o wide, which shows each one's subject, and remember a ClusterRoleBinding can also be granting that permission from outside the namespace. The authoritative answer is always kubectl auth can-i with --as, because it asks the authorizer and not your reading of the manifests.

- **Symptom (step 2):** I cannot find the leaked value: the get event has no requestObject
  **What to do:** And it never will, because a get request sends no body: what you are looking for is responseObject, which is what the API server returned. Inside it sits data.clave in base64, and you have to decode it. If you cannot see responseObject either, you are looking at the ResponseStarted stage event or at the attempt that failed with 403, which returned nothing. Filter on responseStatus.code equal to 200.

- **Symptom (step 3):** kubectl exec -it tells me it cannot use a terminal because I am not in an interactive session
  **What to do:** kubectl -t only allocates a terminal in the container if your own process has one. From a normal terminal, kubectl exec -it is enough. From a script, a pipeline or an editor with no terminal, you have to ask script(1) for it, a util-linux tool made for this: script -q -c "<your kubectl exec -it command>" /dev/null. That is how this lab's own setup does it and how the check does it.

- **Symptom (step 3):** The cameras file is full of Drop and execute new binary in container alerts I did not cause
  **What to do:** They are real and they are not yours. That rule fires when a process runs a binary that did not come in the base image, and the kubelet, the network plugins and any other container on your machine can do that at any moment. Falco is watching the whole kernel, not only this cluster. Always filter by the rule name you care about and then by container id, which is what the check does. On a production cluster, that noise is the work that has to be done before a runtime detector is useful: tuning.

- **Symptom (step 4):** I set readOnlyRootFilesystem and the Pod goes into CrashLoopBackOff
  **What to do:** That is what has to happen before you mount the drawers, and it is half the exercise. Read the container log with kubectl -n el-local logs <pod> and you will see the first place it could not write, with the Read-only file system message. Mount an emptyDir there, try again, and repeat until it starts. Do not guess the directory list: the application tells you one by one which one it is missing. If you prefer to get ahead of it, read the Deployment's command field, which is where all the startup writes are written down.

- **Symptom (step 4):** My log records the exec with verb create and the lab says it got get
  **What to do:** Both are correct, and that is why that deliverable line is graded against your log and not against a constant. The verb depends on the transport your client negotiates: modern kubectl uses WebSocket, which is a GET request with a protocol upgrade, and so it is recorded as get; the old SPDY transport used POST and came out as create. If you forced the old transport with the corresponding environment variable, you will see create and you will be right. Write down whatever your event says.

## Going further

- Go back to Step 1 and change the audit policy: add a rule with level None for the kubernetes-admin user, before the Secrets rule. Recreate the cluster, repeat the Step 1 action and watch the log go silent for your own user. Write three lines on why an attacker who reaches the node would rather edit the policy than delete the log file, and on which control from Chapters 1 to 4 would have got in their way.
- In Step 2, measure the cost of the RequestResponse level. Change the policy so ConfigMaps are also at RequestResponse, recreate the cluster, run something that generates traffic and compare the audit file size after five minutes against the one this lab produces. Then decide, in writing, which resources you would leave at that level on a production cluster and which you would not, knowing that the level that gives you the evidence is the same one that puts your secrets into a text file.
- In Step 3, write your own Falco rule in /etc/falco/rules.d instead of using one of the shipped ones. For instance, one that fires when somebody reads /etc/shadow inside a container, which unlike the exercise's rule needs no terminal. Compare it with the canonical rule and note which fields you had to use. Writing a rule is a good way to understand why the exercise's one asked for proc.tty.
- In Step 4, go one rung higher: on top of the read-only root filesystem, make the container run as a non-root user, with runAsNonRoot and runAsUser, and with allowPrivilegeEscalation set to false. Watch what breaks first and why, and fix only what needs fixing. Then compare your Pod against what the restricted profile of the Pod Security Standards demands and note what it is still missing.
- Put the four steps together into a single correlation exercise, which is what is done in a real incident: trigger the Step 3 alert on the Step 4 Pod and then, using only the alert's timestamp, find in the log the exec event that produced it and the identity that opened it. Write the full timeline. Falco tells you what happened inside the container; auditing tells you who asked for it from outside. Neither one alone closes the case.

## References

- Kubernetes documentation, Auditing. The reference for the audit backend, the four levels, the stages and the --audit-policy-file and --audit-log-path flags this lab drives. https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/
- Kubernetes API reference, Auditing Configuration (audit.k8s.io/v1). The authoritative schema of the Policy object and of the Event object the checks parse, including level, stage, objectRef, user and responseObject. https://kubernetes.io/docs/reference/config-api/apiserver-audit.v1/
- Kubernetes API reference, kubeadm Configuration v1beta4. Documents the structured extraArgs list and the extraVolumes HostPathMount fields used to hand the audit policy to the API server through kind's kubeadmConfigPatches. https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/
- kind documentation, Configuration. Documents kubeadmConfigPatches and nodes[].extraMounts, which is how the audit policy file reaches the node before the API server starts. https://kind.sigs.k8s.io/docs/user/configuration/
- kind documentation, Quick Start. Documents cluster creation and the --kubeconfig flag this lab uses for isolation. https://kind.sigs.k8s.io/docs/user/quick-start/
- kind release v0.32.0. Source of the pinned kindest/node:v1.36.1 image digest this lab runs on, verified 2026-08-21. https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0
- Falco documentation, Rules. Documents the rule fields (condition, output, priority, tags) and the enabled flag that Step 3's anti-shortcut check defeats. https://falco.org/docs/concepts/rules/
- Falco documentation, Falco Rules (default ruleset). The reference for the Terminal shell in container rule Step 3 triggers. https://falco.org/docs/reference/rules/default-rules/
- Falco documentation, Kernel Events. Documents the modern eBPF driver this lab selects with engine.kind=modern_ebpf and its kernel requirements. https://falco.org/docs/concepts/event-sources/kernel/
- Falco documentation, Deploy as a container. Documents the container mounts and privileges the Step 3 DaemonSet reproduces. https://falco.org/docs/setup/container/
- Falco release 0.44.1. Source of the pinned falcosecurity/falco image digest this lab runs on, verified 2026-08-21. https://github.com/falcosecurity/falco/releases/tag/0.44.1
- Kubernetes documentation, Configure a Security Context for a Pod or Container. Documents readOnlyRootFilesystem, privileged and the rest of the container security context Step 4 sets. https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Kubernetes documentation, Pod Security Standards. Defines the restricted profile the Step 4 extension compares against. https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Kubernetes documentation, Volumes. Documents emptyDir, the scratch volume Step 4 mounts, and hostPath, the shortcut Step 4 forbids. https://kubernetes.io/docs/concepts/storage/volumes/
- Kubernetes documentation, Using RBAC Authorization. Documents Role, RoleBinding and ServiceAccount subjects, the objects Step 2's incident and containment are made of. https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Kubernetes documentation, Authorization. Documents kubectl auth can-i and the --as impersonation flag Step 2's containment check is graded with. https://kubernetes.io/docs/reference/access-authn-authz/authorization/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
