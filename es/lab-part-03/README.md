# Parte III - Laboratorio: un uniforme que le quita llamadas al sistema, un candado hecho a la medida del local, una bodega donde se puede leer pero no escribir, y un patio al que alguien le abrió una salida trasera

- Tiempo: 60 min
- Puntos: 40

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solo el objetivo y el entregable, y la secuencia de comandos que lo resuelve vive en el campo cmd de ese paso para que usted la revele después de haberlo intentado con sus propias manos. El Paso 1 le pone al celador el uniforme reglamentario, seccompProfile RuntimeDefault, y le exige demostrar que ese uniforme efectivamente le quita llamadas al sistema: al lado hay un celador gemelo sin uniforme que el setup dejó puesto, y la calificación compara los dos en vivo, así que borrar el gemelo o vestirlo también hace perder el paso. El Paso 2 manda cortar un candado a la medida: un perfil seccomp propio, escrito en JSON e instalado en el disco del nodo, que deja trabajar al contenedor pero le prohíbe una familia de llamadas concreta; la calificación entra al nodo a leer el archivo del perfil, así que borrarlo después de que el Pod arrancó hace fallar el paso. El Paso 3 baja al patio de la bodega con AppArmor: usted carga un perfil de deny-write en el nodo y se lo pone al Pod por el campo appArmorProfile, y la calificación no le cree al manifiesto, sino que le pregunta al proceso vivo bajo qué perfil corre y en qué modo, de manera que cargarlo en complain o poner el tipo Unconfined falla aunque el YAML se vea bonito. El Paso 4 le entrega el patio con una salida trasera que alguien abrió sin permiso: usted tiene que inventariar con ss todo lo que el nodo tiene escuchando, justificar por escrito cada puerto que sí debe estar, y cerrar el que sobra sin que se le caiga el plano de control; la calificación exige el puerto cerrado, la unidad que lo abría desactivada para que no vuelva sola, y el kubelet y los siete puertos del plano de control todavía sanos, así que apagar servicios a lo bruto para que ss quede callado también es reprobar.

## Prerrequisitos

- Una máquina Linux con kind, kubectl y docker en el PATH, acceso a internet, y al menos 4 GB de RAM libre. Este laboratorio crea su propio clúster de kind llamado cks-p03, de un solo nodo, y lo borra al final. Todo lo que hace pasa por un kubeconfig privado en ~/cks-lab/p03/kubeconfig, que se pasa con --kubeconfig en cada comando: su kubeconfig de siempre nunca se toca, su contexto actual nunca cambia, y ningún otro clúster suyo se ve afectado. No ejecute este laboratorio contra un clúster de producción.
- Versiones con las que se ejecutó este laboratorio el 2026-10-11: kind v0.33.0, kubectl cliente v1.37.0, Docker 29.9.0, nodo con Kubernetes v1.36.1, imagen de nodo kindest/node:v1.36.1 fijada por digest sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, y la imagen de carga de trabajo busybox:1.37.0 fijada por digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Confirme su kind con kind version y su kubectl con kubectl version --client antes de empezar, en vez de creerle a este párrafo.
- Su kernel tiene que traer AppArmor activo. Un nodo de kind no es una máquina virtual: es un contenedor que comparte el kernel de su computador, así que seccomp y AppArmor los pone el kernel del host, no el clúster. Compruébelo usted mismo con cat /sys/module/apparmor/parameters/enabled, que en la máquina donde se ejecutó este laboratorio devuelve Y. Si le devuelve N, o si el archivo no existe, el setup se detiene con el error SUSTRATO_SIN_APPARMOR_EN_EL_HOST y le dice qué falta: los Pasos 1, 2 y 4 funcionarían igual, pero el Paso 3 quedaría calificando un control que nadie aplica, y eso es decoración.
- Lea esto antes de correr el setup, porque toca su máquina y no solo el clúster. Para que AppArmor funcione dentro de un nodo de kind hacen falta tres cosas que la imagen del nodo no trae: montar securityfs en /sys/kernel/security dentro del nodo, dejar el binario apparmor_parser adentro, y reiniciar containerd, porque containerd decide una sola vez al arrancar si el host soporta AppArmor y se queda con esa respuesta. El setup hace las tres. La consecuencia que usted tiene que conocer: un perfil de AppArmor cargado así no vive dentro del clúster, vive en el espacio de nombres raíz de AppArmor de su kernel, y sobrevive a kind delete clúster. Por eso todos los perfiles de este laboratorio empiezan por cks-p03- y por eso el teardown los descarga del kernel antes de borrar el clúster. Si interrumpe el laboratorio de forma abrupta, descárguelos a mano con el comando que aparece en el teardown.
- El setup no se limita a construir el clúster: le hace tres pruebas de sustrato antes de dejarlo empezar, porque los cuatro pasos dan por hecho comportamientos que un clúster puede aceptar por API y no aplicar en la práctica. Comprueba que seccomp RuntimeDefault bloquee una llamada al sistema que sin él sí pasa, que un perfil Localhost puesto en el disco del nodo llegue efectivamente al contenedor, y que un perfil de AppArmor quede en enforce sobre el proceso. Si alguna falla, el setup imprime un error con nombre propio y se detiene.
- Haber leído los Capítulos 5 y 6. Este laboratorio no vuelve a explicar qué es una llamada al sistema, qué diferencia hay entre seccomp y una capability, ni por qué un puerto abierto de más es una puerta abierta de más; le hace operar las cuatro cosas contra un clúster real y las califica contra su estado real.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 6: El uniforme reglamentario del celador, y el gemelo que se quedó en ropa de calle (10 pts)

El Capítulo 6 le contó que el uniforme del celador no es un adorno: es la lista de cosas que él puede hacer adentro del conjunto, y todo lo que no esté en esa lista simplemente no se puede. Seccomp es la misma idea, pero la lista es de llamadas al sistema y quien la revisa es el kernel, no la portería.

Es fácil escribir `seccompProfile: RuntimeDefault` en el manifiesto, ver el Pod en Running y dar el trabajo por hecho. Ahí está el problema: un campo aceptado por el API server no es un filtro cargado en el kernel. La única prueba que vale es preguntarle al proceso vivo, y el proceso vivo se lo dice en `/proc/1/status`, en la línea `Seccomp:`, que vale 0 si no hay nada, 1 en modo estricto y 2 cuando hay un filtro puesto.

Falta todavía un detalle que es fácil pasar por alto. Que una llamada al sistema falle dentro de un contenedor no prueba que seccomp la haya bloqueado. En un contenedor normal fallan montones de llamadas por otra razón completamente distinta: porque piden una capability que el contenedor no tiene. Si usted prueba con una de esas, va a ver un Operation not permitted que no demuestra nada, porque habría fallado igual sin seccomp. Por eso este paso le deja un gemelo al lado: el mismo contenedor, la misma imagen, las mismas capabilities, sin uniforme. La prueba no es que su Pod falle. La prueba es que el gemelo lo logra y el suyo no.

Un error costoso en este paso es quitarle el uniforme al gemelo para que "los dos den igual", o borrarlo porque estorba, o dejarlo caer sin darse cuenta. Ese Pod que usted no creó es el instrumento de medición del paso. Sin él lo único que le queda es un contenedor que falla, y un contenedor que falla no es un contenedor asegurado; puede ser simplemente un contenedor roto.

ENTREGABLE: el Pod `celaduria-con-uniforme` corriendo en el namespace `conjunto`, con el perfil seccomp por defecto del runtime declarado, el gemelo `celaduria-sin-uniforme` intacto, como lo dejó el setup, y el archivo `~/cks-lab/p03/01-respuesta.txt`, exactamente 3 líneas:

```text
MODO_SECCOMP_CON_UNIFORME=<el número de la línea Seccomp: de /proc/1/status dentro de su Pod>
MODO_SECCOMP_SIN_UNIFORME=<el mismo número, medido dentro del gemelo>
LLAMADA_BLOQUEADA=<la bandera hexadecimal que el mensaje de error nombra cuando su Pod intenta crear un user namespace, escrita tal cual la imprime>
```

<details>
<summary>Qué debería ver</summary>

La primera consulta imprime gemelo=Unconfined, que es lo que el setup le dejó puesto al celador sin uniforme. El Pod nuevo arranca sin problemas y los dos grep sobre /proc/1/status devuelven Seccomp: 2 para el que tiene uniforme y Seccomp: 0 para el gemelo; el 2 es SECCOMP_MODE_FILTER y el 0 es SECCOMP_MODE_DISABLED, según proc(5). Ahí está la primera prueba, y no viene del manifiesto sino del kernel. El unshare -U sobre el gemelo no imprime nada y devuelve gemelo_unshare_rc=0, o sea que crear un user namespace es posible sin seccomp y sin ninguna capability añadida. El mismo comando sobre el celador con uniforme imprime unshare: unshare(0x10000000): Operation not permitted y devuelve uniforme_unshare_rc=1. Ese 0x10000000 es CLONE_NEWUSER, y la única diferencia entre los dos Pods es el perfil de seccomp: misma imagen, mismas capabilities, mismo nodo. Las dos últimas líneas son el control negativo del paso: unshare -m falla en los dos, con unshare: unshare(0x20000): Operation not permitted, porque 0x20000 es CLONE_NEWNS y eso pide CAP_SYS_ADMIN, que ninguno de los dos tiene. Fallar no prueba que seccomp actuó; lo que lo prueba es que uno falla y el otro no.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 6: Un candado cortado a la medida del local, guardado en el disco del nodo (10 pts)

El perfil del runtime está pensado para cargas genéricas, y ese es su límite: es un candado de ferretería, cortado para una puerta promedio. El Capítulo 6 hablaba del uniforme limitado; este paso es el sastre. Un perfil Localhost es un perfil que usted escribe, que usted guarda en el disco del nodo, y que el kubelet le pasa al runtime por nombre.

Lo que pasa es que "en el disco del nodo" es literal. `localhostProfile` no es una ruta del sistema de archivos suyo ni un ConfigMap: es una ruta relativa a la raíz de perfiles del kubelet, que en Linux es `/var/lib/kubelet/seccomp`. El archivo tiene que estar en cada nodo donde el Pod pueda aterrizar, puesto ahí antes de que el Pod arranque, y si no está, el contenedor no se queda esperando: se cae con CreateContainerError. En este laboratorio el nodo es un contenedor de docker, así que usted entra con `docker exec`; en un clúster real entraría por SSH, o dejaría el archivo con un DaemonSet, o usaría el Security Profiles Operator.

La otra mitad del oficio es escoger la acción por defecto. Un perfil con `defaultAction` en `SCMP_ACT_ERRNO` niega todo lo que no esté en la lista, y suena riguroso hasta que se advierte que un contenedor moderno hace cientos de llamadas distintas solo para arrancar, y que a la primera que falte el proceso muere antes de imprimir nada. Por eso el ejercicio empieza por el otro lado: permitir por defecto y negar una familia concreta. Es menos elegante y es mucho más honesto como primer perfil.

Un atajo tentador es dejar el perfil puesto mientras el Pod arranca y borrar el archivo después, porque "ya quedó aplicado". Es verdad que queda aplicado, el filtro vive en el kernel y el Pod sigue confinado. Y también es verdad que el día que ese Pod se reinicie, o que el nodo se reponga, o que el ReplicaSet cree otro, el candado ya no existe y nadie se va a enterar. Por eso la calificación entra al nodo a mirar si el archivo sigue ahí.

ENTREGABLE: el archivo de perfil `/var/lib/kubelet/seccomp/profiles/candado-del-local.json` en el nodo `cks-p03-control-plane`, un perfil que deje trabajar al contenedor pero le niegue la familia de llamadas `chmod`; el Pod `tienda-del-conjunto` en el namespace `conjunto` usándolo por `localhostProfile`; y el archivo `~/cks-lab/p03/02-respuesta.txt`, exactamente 2 líneas:

```text
RUTA_DEL_PERFIL=<el valor de localhostProfile que su Pod declara, leído del clúster>
ACCION_POR_DEFECTO=<el valor de defaultAction que tiene el archivo del perfil en el nodo>
```

<details>
<summary>Qué debería ver</summary>

El cat sobre el archivo del nodo le devuelve el JSON como lo escribió, con defaultAction en SCMP_ACT_ALLOW y una sola entrada de syscalls que le pone SCMP_ACT_ERRNO a la familia chmod. El Pod arranca sin problemas, porque un perfil que permite por defecto no le quita al contenedor nada que necesite para vivir. El grep devuelve Seccomp: 2, igual que en el Paso 1: para el kernel no hay diferencia entre el perfil del runtime y el suyo, los dos son un filtro BPF cargado. El touch funciona y devuelve touch_rc=0. El chmod imprime chmod: /tmp/inventario: Operation not permitted y devuelve chmod_rc=1, que es el errnoRet 1 (EPERM) que usted pidió en el perfil. Y la última consulta imprime ruta=profiles/candado-del-local.json: fíjese en que es una ruta relativa, sin barra inicial, porque localhostProfile se interpreta contra la raíz de perfiles del kubelet, que en Linux es /var/lib/kubelet/seccomp. Si usted escribe ahí la ruta absoluta, el kubelet no encuentra el archivo y el contenedor se queda en CreateContainerError.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 6: La bodega donde se puede mirar todo y no se puede escribir nada (10 pts)

Seccomp decide qué llamadas al sistema puede hacer un proceso. AppArmor decide sobre qué puede hacerlas: qué archivos, qué rutas, qué capacidades, qué red. Son capas distintas y se suman, y el Capítulo 6 las trató juntas por esa razón: el uniforme dice qué puede hacer el celador, y el perfil dice en qué parte del conjunto.

AppArmor en Kubernetes tiene una regla que conviene conocer de entrada: el clúster no reparte perfiles. No hay un objeto AppArmorProfile, no hay un ConfigMap que se sincronice solo. El perfil tiene que estar cargado en el kernel de cada nodo donde el Pod pueda aterrizar, antes de que el Pod arranque, y usted lo pone ahí por fuera de Kubernetes: con `apparmor_parser`, por SSH, con un DaemonSet, o con el Security Profiles Operator. El campo `appArmorProfile` de Kubernetes solo nombra un perfil que ya existe.

Y la palabra que se paga en el examen es `enforce`. AppArmor carga perfiles en dos modos: enforce, que niega efectivamente, y complain, que no niega nada y solo escribe en el log de auditoría lo que habría negado. Complain existe para desarrollar perfiles sin romper nada, y es una herramienta excelente. También es la forma más silenciosa de creer que un sistema está asegurado cuando no lo está. Un perfil en complain se ve idéntico en el manifiesto, se ve idéntico en `kubectl describe`, y solo se delata cuando uno lee el modo en el que quedó.

Un atajo que parece elegante: cuando el Pod no arranca por culpa del perfil, cambiar el tipo a `Unconfined` para "salir del paso" y seguir con el laboratorio. El Pod arranca en tres segundos, el YAML sigue teniendo la sección appArmorProfile, y todo se ve bien. Lo único que cambió es que ya no hay perfil. Por eso la calificación no lee el manifiesto: le pregunta al proceso número 1 del contenedor bajo qué perfil está corriendo, y eso no se puede escribir a mano.

ENTREGABLE: un perfil de AppArmor llamado `cks-p03-bodega-sin-lapicero`, cargado en modo enforce en el nodo `cks-p03-control-plane`, que niegue toda escritura y permita la lectura; el Pod `bodega` en el namespace `conjunto` corriendo bajo ese perfil por el campo `appArmorProfile`; y el archivo `~/cks-lab/p03/03-respuesta.txt`, exactamente 2 líneas:

```text
PERFIL_DEL_PROCESO=<lo que devuelve cat /proc/1/attr/current dentro del Pod bodega, tal cual, con el paréntesis>
MODO_EN_EL_NODO=<la palabra que aparece entre paréntesis al lado de su perfil en la lista de perfiles cargados del nodo>
```

<details>
<summary>Qué debería ver</summary>

El apparmor_parser no imprime nada cuando le va bien, que es lo normal en las herramientas de AppArmor, y el grep siguiente le confirma la carga con la línea cks-p03-bodega-sin-lapicero (enforce). Esa palabra entre paréntesis es la mitad del paso: enforce quiere decir que niega, complain quiere decir que solo anota en el log y deja pasar. El Pod arranca y queda Ready. El cat de /proc/1/attr/current imprime cks-p03-bodega-sin-lapicero (enforce), que es el perfil visto desde adentro del contenedor, por el propio proceso. El cat de /etc/hostname imprime bodega y devuelve lectura_rc=0, porque el perfil dice file, que permite el acceso a archivos, y solo después niega la escritura. El touch imprime `touch: /tmp/remision: Permission denied` y devuelve escritura_rc=1. Fíjese en la diferencia de vocabulario con el Paso 1: seccomp devuelve Operation not permitted porque el filtro responde EPERM a la llamada, y AppArmor devuelve Permission denied porque el LSM niega el acceso al archivo. Son dos capas distintas del kernel diciendo que no por dos razones distintas.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 5: El patio con una salida trasera que nadie autorizó (10 pts)

El Capítulo 5 hablaba de la pieza vacía: cada cuarto que nadie usa, cada puerta que nadie vigila, cada servicio instalado "por si acaso" es superficie que alguien puede tocar. Y el Capítulo 6 hablaba del patio sin salida trasera. Este paso los junta sobre el nodo mismo, que es la máquina que sostiene el clúster y tiene su propia superficie.

En un nodo de Kubernetes hay dos clases de puerto y confundirlas cuesta caro. Los que escuchan en 127.0.0.1 solo se alcanzan desde adentro de la máquina: el healthz del kubelet, las métricas de kube-proxy, el controller-manager, el scheduler, etcd para su propio plano. Y los que escuchan en la IP del nodo o en el comodín se alcanzan desde la red: el API server en 6443, el kubelet en 10250, el healthz de kube-proxy en 10256, etcd en 2379 y 2380 entre miembros. Esa segunda lista es la superficie de ataque real del nodo, y es una lista corta que usted debería poder recitar.

El trabajo aquí no es memorizar puertos, es aprender a preguntarle a la máquina y a justificar lo que encuentre. `ss -lntp` le dice qué escucha y qué proceso lo abrió. Pero cuando el proceso es systemd con pid 1, ss no le puede decir más, y ahí es donde hay que cambiar de herramienta: `systemctl list-sockets` le da el nombre de la unidad, y con el nombre ya puede leer el archivo, entender qué activa y decidir.

El error costoso aquí es cerrar a lo bruto. Cuando uno ve una lista de puertos que no entiende, la tentación es apagar servicios hasta que la lista se ponga corta. Ahí es donde alguien detiene el kubelet "porque 10250 se ve peligroso" y se lleva por delante el nodo entero, o mata etcd y se lleva el clúster. Endurecer no es apagar: es saber cuál puerto es de quién, por qué tiene que estar, y quitar únicamente el que no tiene dueño. Y cerrar tampoco es detener: una unidad de socket detenida pero habilitada vuelve sola en el siguiente arranque, y usted se queda pensando que cerró algo.

ENTREGABLE: el nodo `cks-p03-control-plane` sin ningún puerto TCP escuchando hacia fuera que no sea de Kubernetes, sin unidades de socket habilitadas, con el kubelet sano y el nodo Ready; y el archivo `~/cks-lab/p03/04-respuesta.txt` con una línea por cada uno de los siete puertos del plano de control (2379, 2380, 6443, 10250, 10256, 10257, 10259), en este formato exacto, con barras verticales y sin espacios alrededor de ellas:

<puerto>|<nombre del proceso tal como lo reporta ss>|<su justificación, al menos 25 caracteres>

Por ejemplo, una línea del archivo se ve así: `6443|kube-apiserver|Es la unica puerta de entrada a la API del cluster y la usan kubectl y todos los nodos.`

<details>
<summary>Qué debería ver</summary>

El primer ss le muestra el inventario completo del nodo, y conviene leerlo despacio porque no todos los puertos son iguales. Sobre 127.0.0.1 escuchan el healthz del kubelet en 10248, las métricas de kube-proxy en 10249, kube-controller-manager en 10257, kube-scheduler en 10259, etcd en 2379 y sus métricas en 2381, más un puerto alto y variable de containerd; sobre 127.0.0.11 escucha el DNS interno de docker, también con puerto variable. Todo eso solo se alcanza desde el propio nodo. La segunda salida deja únicamente lo que escucha en direcciones alcanzables desde fuera, y en un nodo limpio son cinco: la IP del nodo en 2379 y 2380 para etcd, y el comodín en 6443 para kube-apiserver, 10250 para el kubelet y 10256 para el healthz de kube-proxy. En la máquina donde se ejecutó este laboratorio el 2026-10-11 aparece una sexta, en 34521, que no pertenece a esa lista. El systemctl list-sockets le dice quién la abrió, con nombre de unidad y de servicio, que es información que ss no le da porque ss solo puede decirle que el proceso es systemd con pid 1. Después del disable el segundo ss ya no la muestra, is-active devuelve active y el healthz devuelve kubelet_healthz=200, y el nodo sigue Ready.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

## Cómo correrlo

```bash
./00-setup.sh                  # crea el clúster y deja todo listo
./01-step.sh && ./01-check.sh  # haga el paso, compruebe que quedó bien
./02-step.sh && ./02-check.sh
./03-step.sh && ./03-check.sh
./04-step.sh && ./04-check.sh
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

## Si algo falla

- **Síntoma (step 1):** La llamada que escogí para probar falla en los dos Pods, con y sin uniforme
  **Qué hacer:** Escogió una llamada al sistema que pide una capability, no una que seccomp filtre por su cuenta. El perfil por defecto de containerd tiene un grupo entero de llamadas que solo se permiten si el contenedor tiene CAP_SYS_ADMIN (mount, setns, unshare, syslog, bpf, perf_event_open y varias más), y esas mismas llamadas también fallan sin seccomp porque el kernel pide la capability. El caso limpio es distinto: unshare con CLONE_NEWUSER no necesita ninguna capability en un kernel que permite user namespaces sin privilegios, así que sin seccomp pasa y con RuntimeDefault no. Si en su máquina falla también en el gemelo, su kernel está restringiendo los user namespaces por otra vía; compruébelo con sysctl kernel.apparmor_restrict_unprivileged_userns y sysctl kernel.unprivileged_userns_clone.

- **Síntoma (step 1):** Declaré RuntimeDefault y /proc/1/status sigue diciendo Seccomp: 0
  **Qué hacer:** Revise dónde puso el campo. seccompProfile vive bajo securityContext, y el securityContext del Pod está en spec.securityContext mientras que el del contenedor está en spec.containers[N].securityContext; si lo escribió suelto bajo spec, o bajo el contenedor pero fuera de securityContext, el API server puede aceptar el manifiesto y no aplicar nada. Léalo de vuelta del clúster, no del archivo, con kubectl --kubeconfig ~/cks-lab/p03/kubeconfig -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.spec.securityContext.seccompProfile}{.spec.containers[0].securityContext.seccompProfile}'. Y recuerde que el campo no se puede cambiar en un Pod ya creado: hay que borrarlo y volverlo a crear.

- **Síntoma (step 2):** El Pod se queda en CreateContainerError y el evento dice que no encuentra el perfil
  **Qué hacer:** Suele ser un problema de ruta. localhostProfile se resuelve contra la raíz de perfiles del kubelet, /var/lib/kubelet/seccomp en Linux, así que el valor correcto es relativo y sin barra inicial: profiles/candado-del-local.json, no /var/lib/kubelet/seccomp/profiles/candado-del-local.json. Confirme que el archivo exista donde el kubelet lo va a buscar con docker exec cks-p03-control-plane ls -l /var/lib/kubelet/seccomp/profiles/ y lea el evento completo con kubectl --kubeconfig ~/cks-lab/p03/kubeconfig -n conjunto describe pod tienda-del-conjunto. Otra causa posible es un JSON mal formado: el runtime no lo puede parsear y el error se ve parecido.

- **Síntoma (step 2):** El contenedor arranca y se muere de inmediato, sin log útil
  **Qué hacer:** Probablemente puso defaultAction en SCMP_ACT_ERRNO sin una lista de permitidas suficiente, y el proceso murió antes de poder escribir nada. Para diagnosticarlo sin adivinar, cambie temporalmente defaultAction a SCMP_ACT_LOG, que deja pasar todo pero registra cada llamada, vuelva a crear el Pod y lea los mensajes de auditoría del kernel; con esa lista ya puede construir un perfil de negar por defecto que sí funcione. Para este paso, sin embargo, no hace falta: el entregable pide un perfil que permita por defecto y niegue una familia, que es el camino corto y el que se puede verificar.

- **Síntoma (step 3):** El Pod se queda en estado AppArmor y el evento dice Cannot enforce AppArmor: AppArmor is not enabled on the host
  **Qué hacer:** Ese mensaje viene del kubelet, y el kubelet decide si AppArmor está disponible mirando tres cosas: que /sys/module/apparmor/parameters/enabled diga Y, que exista el directorio /sys/kernel/security/apparmor y que apparmor_parser esté en el PATH del nodo. El setup monta securityfs y deja el parser, pero el kubelet toma esa decisión al arrancar, así que si usted lo tocó después hay que reiniciarlo: docker exec cks-p03-control-plane systemctl restart kubelet. Compruebe las tres condiciones a mano con docker exec cks-p03-control-plane sh -c 'cat /sys/module/apparmor/parameters/enabled; ls /sys/kernel/security/apparmor; command -v apparmor_parser'.

- **Síntoma (step 3):** El Pod se queda en CreateContainerError y el mensaje dice apparmor is not supported, o apparmor profile not found
  **Qué hacer:** Son dos causas distintas con arreglos distintos. Si dice apparmor is not supported, el que no está convencido es containerd, no el kubelet: containerd hace ese chequeo una sola vez al arrancar y se queda con la respuesta, así que si securityfs se montó después, hay que reiniciarlo con docker exec cks-p03-control-plane systemctl restart containerd y esperar a que el nodo vuelva a Ready. Si dice apparmor profile not found seguido de un nombre, el perfil sencillamente no está cargado en ese nodo: revise el nombre exacto, que es el que va dentro del archivo de perfil después de la palabra profile y no el nombre del archivo, y confírmelo con docker exec cks-p03-control-plane grep cks-p03 /sys/kernel/security/apparmor/profiles.

- **Síntoma (step 3):** Descargué el perfil del kernel para corregirlo, lo volví a cargar en enforce, y ahora el Pod dice unconfined
  **Qué hacer:** Es el comportamiento correcto y conviene verlo una vez. El perfil se le asigna al proceso cuando el contenedor arranca; si usted lo descarga del kernel mientras el Pod está vivo, el proceso se queda sin etiqueta y /proc/1/attr/current pasa a decir unconfined, y volver a cargar el perfil con el mismo nombre no se la devuelve, porque nadie vuelve a etiquetar un proceso que ya está corriendo. Lo confuso es que en esa situación algunas escrituras pueden seguir fallando por otras razones, así que la salida de un touch no le sirve para saber si quedó bien. La regla práctica: cada vez que toque el perfil en el nodo, borre el Pod y vuélvalo a crear, y confirme siempre leyendo /proc/1/attr/current, que es lo mismo que hace la calificación.

- **Síntoma (step 4):** ss me dice que el puerto lo abrió systemd con pid 1 y ahí se acabó la pista
  **Qué hacer:** No se acabó, cambió de herramienta. Cuando systemd tiene el socket, es porque hay una unidad de tipo .socket que lo abrió, normalmente para activar un servicio bajo demanda. Pregúntele a systemd directamente con docker exec cks-p03-control-plane systemctl list-sockets, que le da tres columnas: la dirección escuchada, la unidad de socket y el servicio que activa. Con el nombre de la unidad ya puede leerla completa con systemctl cat <unidad> y ver el ListenStream y el ExecStart de lo que activa. Para cerrarla del todo hay que deshabilitarla, no solo detenerla, porque enabled significa que vuelve sola en el próximo arranque.

- **Síntoma (step 4):** Cerré el puerto que sobraba y la comprobación sigue fallando
  **Qué hacer:** Revise las cuatro exigencias por separado, porque la comprobación pide más que el puerto cerrado. Primera, que no quede ninguna unidad de socket en estado enabled: mírelo con docker exec cks-p03-control-plane systemctl list-unit-files --type=socket y busque la palabra enabled en la segunda columna. Segunda, que los siete puertos del plano de control sigan escuchando: si en el camino detuvo un servicio, vuelva a levantarlo. Tercera, que el kubelet siga active y su healthz en 127.0.0.1:10248 devuelva 200. Cuarta, el formato del archivo: las líneas van sin espacios alrededor de las barras, el nombre del proceso tiene que ser el que ss reporta en ese momento, que viene recortado a 15 caracteres por el kernel (por eso kube-controller-manager aparece como kube-controller), y la justificación tiene que tener al menos 25 caracteres.

## Para ir más lejos

- Vuelva al Paso 2 y cámbiele al perfil de la tienda el defaultAction a SCMP_ACT_LOG, sin tocar la lista de syscalls, y vuelva a crear el Pod. Ahora nada se bloquea, pero el kernel escribe en su registro de auditoría cada llamada que el proceso hace. Léalo desde el nodo con docker exec cks-p03-control-plane sh -c 'dmesg | grep -i seccomp' y observe cuántas llamadas distintas necesita un busybox que solo duerme. Ese es el método real para construir un perfil de negar por defecto: primero se mide, después se escribe la lista.
- Cargue el perfil de la bodega en modo complain con apparmor_parser -C en vez de -r, vuelva a crear el Pod y repita las dos pruebas del Paso 3. Va a ver que el nombre del perfil sigue apareciendo en /proc/1/attr/current, que el manifiesto se ve idéntico, y que el touch ahora funciona. Después lea lo que el kernel anotó de esa escritura. Ese ejercicio le muestra, en su propia máquina, por qué la calificación del Paso 3 lee el modo y no solo el nombre.
- Ponga en el namespace conjunto las etiquetas de Pod Security Admission en modo warn con pod-security.kubernetes.io/warn=restricted y vuelva a crear los cuatro Pods del laboratorio tal como los tiene. Lea con calma los avisos del API server: el perfil restricted exige seccompProfile RuntimeDefault o Localhost, así que el celador sin uniforme le va a sacar un aviso y los suyos no. Es una forma de ver la misma regla del Paso 1 aplicada por admisión en vez de por revisión manual.
- Repita el inventario del Paso 4 contra un nodo que sí sea una máquina y no un contenedor: una VM cualquiera con Linux le sirve. Compare las dos listas de ss y fíjese en todo lo que aparece en la VM y no aparece en el nodo de kind (sshd, el cliente de DHCP, el resolvedor local, a veces un servidor de correo que nadie pidió). Esa diferencia es de lo que hablaba el Capítulo 5 cuando decía que la pieza vacía también es superficie.

## Referencias

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
