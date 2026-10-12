# Lo que pasa es que asegurar Kubernetes

**Los laboratorios del libro.** · **The book's labs.**

Si usted llegó aquí desde el libro, está en el lugar correcto. Aquí están los laboratorios del
libro, uno por cada parte, listos para clonar y ejecutar.

If you got here from the book, you are in the right place. These are the book's labs, one per
part, ready to clone and run.

---

## Español

### El libro

**Lo que pasa es que asegurar Kubernetes.** *Guía completa de seguridad en Kubernetes en lenguaje sencillo.*
Quince capítulos en seis partes, con un laboratorio por parte. Cubre los dominios de la
certificación **CKS** (Certified Kubernetes Security Specialist): configuración del clúster,
fortalecimiento del clúster, fortalecimiento del sistema, vulnerabilidades de microservicios,
seguridad de la cadena de suministro, y monitoreo, registro y seguridad en tiempo real. Sigue
la apuesta del resto de la serie: si usted entiende el mecanismo, no tiene que memorizar la
respuesta. La analogía es el conjunto residencial Los Nogales, con su portería, su celador,
sus torres y su tienda.

Material de estudio independiente. No está afiliado a la Linux Foundation ni a la Cloud
Native Computing Foundation, ni cuenta con su respaldo. Los laboratorios imitan el formato
de la certificación (tareas calificadas por el estado final del clúster) y nunca su contenido.

### Qué son estos laboratorios

Cada laboratorio es una práctica de 45 a 60 minutos de trabajo real contra un clúster de
verdad (kind, dentro de Docker). Cada paso le da un objetivo y un entregable, y se califica
por el **estado final del clúster**, no por lo que usted escribió ni por el camino que tomó.
Cada laboratorio se publica aquí solo después de ejecutarlo completo en kind, de principio a fin.

### Cuándo hacer cada laboratorio

Hay un laboratorio por cada parte del libro, y cada uno usa **todo** lo de esa parte, no
solo el último capítulo. El momento de hacerlo es cuando usted termina la parte completa.

| Termine de leer | Y entonces corra | Tiempo | Puntos |
|---|---|---|---|
| Capítulo 2, *La portería con cédula verificada* (cierra la Parte I) | `es/lab-part-01` | 45-60 min | 40 |
| Capítulo 4, *La reja eléctrica que se revisa cada mes* (cierra la Parte II) | `es/lab-part-02` | 55 min | 40 |
| Capítulo 6, *El patio sin salida trasera y el uniforme limitado* (cierra la Parte III) | `es/lab-part-03` | 60 min | 40 |
| Capítulo 9, *La pared propia y el citófono cifrado* (cierra la Parte IV) | `es/lab-part-04` | 55 min | 40 |
| Capítulo 12, *El proveedor autorizado y el sello de garantía* (cierra la Parte V) | `es/lab-part-05` | 55 min | 40 |
| Capítulo 15, *El candado que no se abre a mitad de turno* (cierra la Parte VI) | `es/lab-part-06` | 60 min | 40 |

### Antes de empezar

Necesita estas herramientas instaladas y funcionando:

| Herramienta | Para qué | Versión con la que se probó |
|---|---|---|
| `docker` | correr los nodos del clúster y construir las imágenes de la Parte V | 29.9.0 |
| `kind` | crear los clústeres de práctica | v0.33.0 |
| `kubectl` | hablarle al clúster | v1.37.0 |
| `helm` | instalar el controlador de admisión de la Parte V | v4.3.0 |
| `openssl` | revisar certificados en las Partes I y IV | 3.0.13 |
| `curl` | descargar y probar endpoints en las Partes I y V | 8.5.0 |
| `jq` | leer las respuestas del clúster en los verificadores | 1.7 |
| `script` (util-linux) | reservar una terminal en la Parte VI | 2.39.3 |

Versiones cercanas también sirven. Los clústeres se crean con imágenes `kindest/node` fijadas
por digest (v1.36.1, y v1.34.2 en la Parte II), y los laboratorios necesitan internet al
montarse. Cada `README.md` dice qué más usa ese laboratorio y cuánta memoria pide.

### Empiece aquí

```bash
git clone https://github.com/lfarizav/lo-que-pasa-es-que-asegurar-kubernetes.git
cd lo-que-pasa-es-que-asegurar-kubernetes/es/lab-part-01
cat README.md
```

El repositorio tiene dos carpetas: `es/` (español) y `en/` (inglés). Los scripts son los
mismos; cambia el idioma del `README.md` de cada laboratorio. Cada laboratorio se corre
siempre igual: montaje, cada paso con su verificador, y desmontaje.

```bash
./00-setup.sh                  # crea el clúster y deja todo listo
./01-step.sh && ./01-check.sh  # haga el paso, compruebe que quedó bien
./02-step.sh && ./02-check.sh
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

El verificador imprime `ok` cuando el paso quedó bien y sale con error cuando no. Los
`0N-step.sh` están para que no se quede atascado, pero el laboratorio se aprovecha leyendo el
`README.md` y escribiendo usted los comandos: corra el script para comparar.

### Su clúster de todos los días no se toca

Cada laboratorio crea su propio clúster kind, con su propio archivo de kubeconfig en
`~/cks-lab/pNN/kubeconfig`, y **todos** los `kubectl` del laboratorio pasan `--kubeconfig`
de forma explícita. Su `~/.kube/config` no se lee ni se modifica, y el `99-teardown.sh` borra
únicamente el clúster de ese laboratorio, por nombre. Sus otros clústeres de kind siguen donde
estaban.

Algunos pasos cambian a propósito la configuración del plano de control o del nodo del
clúster del laboratorio, y la Parte VI corre Falco con privilegios, que ve las llamadas al
sistema de todo el kernel de su máquina. Use una máquina de práctica. Nunca corra en
producción un comando de un libro, de un blog o de un video sin entender qué hace. Este libro
incluido.

### Qué hace cada laboratorio

| | Capítulos | Laboratorio |
|---|---|---|
| 1 | 1 y 2 | el reglamento de visitas de la torre tres, la requisa del celador antes del turno, la portería que sí pide cédula, y el guardia nuevo al que le revisan el carné antes de dejarlo entrar |
| 2 | 3 y 4 | un carné al que le quitan la llave maestra, un celador que hace la ronda sin llevar llaves encima, una reja que volvió a pedir cédula, y el reglamento de admisión que alguien había descolgado de la pared |
| 3 | 5 y 6 | un uniforme que le quita llamadas al sistema, un candado hecho a la medida del local, una bodega donde se puede leer pero no escribir, y un patio al que alguien le abrió una salida trasera |
| 4 | 7 a 9 | un reglamento que sí se hace cumplir en la portería, una caja fuerte que se abre por dentro de etcd para ver qué guardó, un empleado de uniforme que igual hace el turno, y un citófono que no le abre a quien no tenga carné |
| 5 | 10 a 12 | la bodega que se adelgaza, la caja que se pide por factura y no por apodo, el proveedor que trae la plaga adentro, y el sello que la portería sí revisa |
| 6 | 13 a 15 | la minuta de la portería que nadie leía, la película del que entró de madrugada, la cámara que solo graba si hay alguien sentado, y el local que no se deja remodelar a mitad de turno |

### Si algo no funciona

Revise primero el `README.md` del laboratorio (sección de problemas frecuentes). Si el
problema sigue, abra un issue contando qué comando falló, con la versión de Kubernetes y el
sistema operativo. Los reportes de error son bienvenidos.

---

## English

### The book

**Here's What's Actually Going On with Kubernetes Security.** *The complete Kubernetes security guide in plain language.*
Fifteen chapters in six parts, with one lab per part. It covers the domains of the **CKS**
(Certified Kubernetes Security Specialist) certification: cluster setup, cluster hardening,
system hardening, minimizing microservice vulnerabilities, supply chain security, and
monitoring, logging and runtime security. It makes the same bet as the rest of the series:
once you understand the mechanism, there is no answer left to memorize. The analogy is the
Los Nogales residential complex, with its front gate, its watchman, its towers and its shop.

Independent study material. Not affiliated with, endorsed by, or sponsored by the Linux
Foundation or the Cloud Native Computing Foundation. The labs emulate the certification's
format (tasks graded on the final state of the cluster) and never its content.

### What these labs are

Each lab is 45 to 60 minutes of real work against a real cluster (kind, inside Docker). Each
step gives you an objective and a deliverable, and is graded on the **final state of the
cluster**, not on what you typed or the path you took. Each lab is published here only after a
complete run on kind, from start to finish.

### When to do each lab

There is one lab per part of the book, and each one uses **everything** in that part, not
just the last chapter. The moment to do it is when you finish the whole part.

| Finish reading | Then run | Time | Points |
|---|---|---|---|
| Chapter 2, *The Front Gate That Checks Your ID* (closes Part I) | `en/lab-part-01` | 45-60 min | 40 |
| Chapter 4, *The Electric Gate That Gets Serviced Every Month* (closes Part II) | `en/lab-part-02` | 55 min | 40 |
| Chapter 6, *The Yard With No Back Exit and the Limited Uniform* (closes Part III) | `en/lab-part-03` | 60 min | 40 |
| Chapter 9, *Your Own Wall and the Encrypted Intercom* (closes Part IV) | `en/lab-part-04` | 55 min | 40 |
| Chapter 12, *The Authorized Supplier and the Seal of Approval* (closes Part V) | `en/lab-part-05` | 55 min | 40 |
| Chapter 15, *The Lock That Does Not Open Mid-Shift* (closes Part VI) | `en/lab-part-06` | 60 min | 40 |

### Before you start

You need these tools installed and working:

| Tool | What for | Version this was tested on |
|---|---|---|
| `docker` | running the cluster's nodes and building the Part V images | 29.9.0 |
| `kind` | creating the practice clusters | v0.33.0 |
| `kubectl` | talking to the cluster | v1.37.0 |
| `helm` | installing the Part V admission controller | v4.3.0 |
| `openssl` | inspecting certificates in Parts I and IV | 3.0.13 |
| `curl` | downloading and probing endpoints in Parts I and V | 8.5.0 |
| `jq` | reading the cluster's answers in the graders | 1.7 |
| `script` (util-linux) | allocating a terminal in Part VI | 2.39.3 |

Nearby versions are fine too. The clusters are created from `kindest/node` images pinned by
digest (v1.36.1, and v1.34.2 in Part II), and the labs need internet access when they are set
up. Each `README.md` says what else that lab uses and how much memory it needs.

### Start here

```bash
git clone https://github.com/lfarizav/lo-que-pasa-es-que-asegurar-kubernetes.git
cd lo-que-pasa-es-que-asegurar-kubernetes/en/lab-part-01
cat README.md
```

The repository has two folders: `es/` (Spanish) and `en/` (English). The scripts are the
same; what changes is the language of each lab's `README.md`. Every lab runs the same way:
setup, each step with its grader, and teardown.

```bash
./00-setup.sh                  # creates the cluster and gets everything ready
./01-step.sh && ./01-check.sh  # do the step, then check that it landed
./02-step.sh && ./02-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

The grader prints `ok` when the step is right and exits with an error when it is not. The
`0N-step.sh` scripts are there so you never get stuck, but you get the most out of a lab by
reading its `README.md` and typing the commands yourself: run the script to compare.

### Your everyday cluster is never touched

Each lab creates its own kind cluster with its own kubeconfig file at
`~/cks-lab/pNN/kubeconfig`, and **every** kubectl in the lab passes `--kubeconfig`
explicitly. Your `~/.kube/config` is neither read nor modified, and `99-teardown.sh` deletes
only that lab's cluster, by name. Your other kind clusters stay where they were.

Some steps deliberately change the control plane or node configuration of the lab's cluster,
and Part VI runs Falco with privileges, so it sees the system calls of your whole machine's
kernel. Use a practice machine. Never run a command from a book, a blog or a video on a
production cluster without understanding what it does. This book included.

### What each lab does

| | Chapters | Lab |
|---|---|---|
| 1 | 1 and 2 | tower three's visiting rules, the watchman's inspection before his shift, the entrance that does ask for ID, and the new guard whose badge gets checked before he is let in |
| 2 | 3 and 4 | a badge that loses its master key, a guard who walks the round carrying no keys at all, a gate that started asking for ID again, and the admission rulebook somebody had taken off the wall |
| 3 | 5 and 6 | a uniform that takes system calls away, a padlock cut to the shape of the shop, a storeroom you may read but never write in, and a yard somebody opened a back exit onto |
| 4 | 7 to 9 | a set of house rules that is enforced at the gate, a safe you open from inside etcd to see what it stored, an employee in uniform who still works the shift, and an intercom that opens for nobody without an ID card |
| 5 | 10 to 12 | the storeroom that goes on a diet, the box ordered by receipt instead of by nickname, the supplier who brings the pest inside, and the seal the door guard checks |
| 6 | 13 to 15 | the gatehouse logbook nobody read, the film of who came in at dawn, the camera that only records when somebody is sitting down, and the shop that refuses to be remodelled mid-shift |

### If something does not work

Check the lab's `README.md` first (troubleshooting section). If the problem persists, open an
issue saying which command failed, with your Kubernetes version and operating system. Bug
reports are welcome.

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
