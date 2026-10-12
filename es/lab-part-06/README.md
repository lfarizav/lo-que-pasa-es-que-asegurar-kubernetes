# Parte VI - Laboratorio: la minuta de la portería que nadie leía, la película del que entró de madrugada, la cámara que solo graba si hay alguien sentado, y el local que no se deja remodelar a mitad de turno

- Tiempo: 60 min
- Puntos: 40

## Objetivo

Este es un laboratorio de estilo examen (Exam-Style): cada paso le indica solo el objetivo, y la secuencia de comandos completa vive en el campo cmd de ese paso, para que usted la revele después de haber intentado resolverlo con sus propias manos. El Paso 2 es además de diagnóstico puro: el clúster le llega con un incidente que ya ocurrió, aplicado por el montaje desde una carga codificada en base64. Eso no es criptografía y no pretende serlo: es una venda de cortesía, para que usted no lea en el mismo script lo que debe reconstruir desde la bitácora. El incidente es el mismo en todas las corridas, y la respuesta completa está en el campo cmd del Paso 2. El clúster nace con la auditoría del API server prendida desde el primer minuto, con una política propia montada por parches de kubeadm, porque una minuta que se abre después del robo no sirve de nada. El Paso 1 le pide hacer una acción que quede anotada, encontrarla en la minuta y responder quién la hizo, con qué verbo, sobre qué recurso y en qué nivel quedó escrita. El Paso 2 le entrega un robo consumado y una sola fuente de verdad: usted reconstruye quién entró, en qué momento le abrieron la puerta y qué se llevó, y después contiene el daño sin destruir la evidencia. El Paso 3 prende las cámaras, con Falco leyendo llamadas al sistema por eBPF moderno, y le pide provocar la alerta canónica de un shell dentro de un contenedor; la regla no dispara con cualquier exec, y averiguar por qué es el trabajo. El Paso 4 le pone candado al local: convertir un Deployment a sistema de archivos raíz de solo lectura sin que la aplicación deje de vender, y comprobar que entrar por la puerta de servicio deja huella en la misma minuta del Paso 1. Ninguna comprobación se conforma con lo que usted escribió: todas vuelven a consultar el clúster en el momento de calificar, las de los Pasos 3 y 4 entran a un contenedor y lo prueban por su cuenta, y todas exigen que el control que estorbaba siga puesto. Apagar la auditoría, silenciar la regla de Falco, borrar la cuenta comprometida o quitar el candado para que el síntoma se calle son los cuatro atajos que este laboratorio castiga.

## Prerrequisitos

- Una máquina Linux x86_64 desechable con kind, kubectl, docker (accesible sin sudo), base64, jq y script (el de util-linux, el que reserva una terminal) en el PATH, y con al menos 6 GB de RAM libres. Confirme cada herramienta con su propio --version antes de empezar; no dé por buena esta prosa. Ejecutado el 2026-10-11 con kind v0.33.0, kubectl cliente v1.37.0 y Docker 29.9.0.
- Aislamiento (no es opcional). El laboratorio crea su propio clúster kind de un nodo llamado cks-p06 y escribe su kubeconfig en un archivo privado, ~/cks-lab/p06/kubeconfig, desde el primer comando. Todos los comandos kubectl de este laboratorio llevan --kubeconfig apuntando a ese archivo, y usted debe hacer lo mismo. No dependa nunca del contexto actual de su ~/.kube/config: si tiene otro clúster abierto, un kubectl delete sin --kubeconfig cae sobre ese y no sobre este. El laboratorio no toca ningún otro clúster, contexto ni contenedor de su máquina.
- Imágenes fijadas por digest (digests verificados el 2026-08-21 y usados sin cambios en la corrida del 2026-10-11). El nodo del clúster: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, la imagen que kind v0.32.0 declara como suya (la corrida del 2026-10-11 usó kind v0.33.0 con esta misma imagen fijada). Las cámaras: falcosecurity/falco@sha256:d0cfe422d6ac0e0f20857798f46c7d7273210e1b064b22821e4e6e7f843cde6b, que es Falco 0.44.1 con el motor modern_ebpf ya incluido en el binario. Las aplicaciones: busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 (BusyBox v1.37.0), que trae el servidor httpd con el que atiende la caja. El Pod mandadero, el teléfono desde el que se llama al Service: curlimages/curl@sha256:d94d07ba9e7d6de898b6d96c1a072f6f8266c687af78a74f380087a0addf5d17. Una etiqueta es mutable y un digest no: los capítulos le enseñan a buscar la versión vigente, y el laboratorio la fija para que el ejercicio sea reproducible.
- La minuta y las cámaras se leen con dos atajos que el montaje deja escritos. La bitácora de auditoría del API server vive dentro del nodo, en /var/log/kubernetes/audit/audit.log, y pertenece a root, así que se lee entrando al contenedor del nodo. El montaje deja `~/cks-lab/p06/bin/minuta`, que hace justo eso, y `~/cks-lab/p06/bin/camaras`, que hace lo mismo con el archivo de alertas de Falco en /var/log/falco/events.txt. Los dos escupen una línea JSON por evento, así que se leen con jq y no a simple vista.
- Salida a internet durante el montaje, para bajar las cuatro imágenes fijadas. La calificación no necesita internet, solo el clúster vivo y el nodo prendido: las comprobaciones consultan el API server, leen la bitácora y el archivo de alertas dentro del nodo, y llaman al Service desde dentro del propio clúster.
- El montaje tarda cerca de un minuto y deja el clúster con un incidente que ya ocurrió, a propósito. Antes de entregarlo hace dos sondeos y se detiene con un error con nombre si alguno falla: uno sobre la minuta (que el API server escriba la bitácora y que la política ponga los Secrets en nivel RequestResponse: `ERROR SONDA-MINUTA-MUDA` y `ERROR SONDA-NIVEL-SECRETOS`) y otro sobre las cámaras (que Falco con modern_ebpf vea un shell con terminal dentro de un contenedor de este nodo: `ERROR SONDA-CAMARAS-CIEGAS`). Si su kernel no deja correr el motor de eBPF moderno, el montaje se detiene ahí en vez de entregarle un Paso 3 sin piso. Para volver a empezar, corra el teardown completo y después el montaje: el incidente se aplica en el montaje, no paso a paso. El teardown borra solo el clúster cks-p06 y el directorio ~/cks-lab/p06.
- Falco corre privilegiado y con hostPID, y por eso ve las llamadas al sistema de todo el kernel de su máquina, no solo las de este clúster. Si tiene otros contenedores o clústeres prendidos, aparecerán alertas que no son suyas: no es un error, es como funciona un agente de tiempo de ejecución en un nodo real. Por eso todas las comprobaciones del Paso 3 amarran la alerta al id de contenedor del Pod del ejercicio y no al nombre de la regla a secas.
- Haber leído los Capítulos 13, 14 y 15. Este laboratorio no vuelve a explicar qué es una política de auditoría, en qué se diferencian los niveles Metadata y RequestResponse, cómo trabaja un detector de tiempo de ejecución ni por qué un contenedor inmutable es más difícil de forzar; le hace operar las tres cosas contra un clúster real al que ya le robaron.
- Una advertencia sobre el Paso 2, que conviene leer antes de empezar: la evidencia de ese paso vive en la bitácora de auditoría, y la bitácora se puede truncar. Si limpia el archivo para que se vea ordenado, pierde el incidente y tendrá que correr el teardown y el montaje otra vez. Lea antes de barrer.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 14: La minuta de la portería que nadie leía (10 pts)

Lo que pasa es que en el conjunto de la esquina compraron un libro de minuta bellísimo, con pasta dura y todo, y lo pusieron en la portería el mismo día que estrenaron celador. Ahí lleva tres años. Nadie ha escrito una línea. Cuando se perdió la bicicleta del 402 fueron a mirar el libro y estaba en blanco, y el administrador dijo la frase de rigor: "es que nadie sabía que había que anotar".

El problema no fue el ladrón: fue que la minuta se abrió después del robo. El Capítulo 14 lo dijo con estas palabras: una bitácora de auditoría no sirve para lo que va a pasar, sirve para lo que ya pasó, y por eso tiene que estar prendida antes. En Kubernetes eso significa que el API server arranca con una política de auditoría montada desde el primer minuto, y en este laboratorio el clúster nació así: la política va montada como archivo dentro del nodo y el API server la recibe por parches de kubeadm, con --audit-policy-file y --audit-log-path.

Ahora bien, una minuta no anota todo igual. La política de este clúster tiene una regla que anota los Secrets en nivel RequestResponse, el más detallado de los cuatro, y una regla final que deja todo lo demás en Metadata. Esa diferencia no es un detalle de configuración: separa "alguien tocó la caja fuerte" de "alguien tocó la caja fuerte y esto fue lo que sacó". El Paso 2 vive entero de esa diferencia, y aquí es donde usted la ve por primera vez.

Su trabajo en este paso es sencillo de decir y menos de hacer sin leer: haga una acción que quede anotada, vaya a la minuta, encuéntrela y conteste con los datos que trae el propio evento. Cuidado con el grupo: no lo invente, léalo del evento. En este clúster el certificado de administrador no viene en el grupo que usted se imagina.

Y la advertencia, que en este paso es la más fácil de cometer: la minuta crece rápido. La tentación de truncarla "para trabajar cómodo" existe, y es lo primero que hace alguien que entró donde no debía. La comprobación crea un sello nuevo después de calificar sus líneas y exige verlo aparecer en la bitácora, así que una minuta apagada o barrida reprueba el paso aunque su archivo de respuestas sea perfecto.

ENTREGABLE: el Secret `libro-de-minuta` creado en el namespace `la-porteria` con la llave `clave`, y el archivo `~/cks-lab/p06/01-respuesta.txt`, exactamente 5 líneas:

```text
USUARIO=<el username que la minuta anotó para esa creación>
GRUPO=<el grupo de ese usuario que aparece en el evento y que no es system:authenticated>
VERBO=<el verbo que quedó anotado>
RECURSO=<el recurso que quedó anotado, en plural, tal como lo escribe la minuta>
NIVEL=<el nivel de auditoría con el que quedó escrito ese evento>
```

<details>
<summary>Qué debería ver</summary>

El Secret se crea sin sobresaltos y tres segundos después ya está anotado. El evento que devuelve la minuta es un objeto JSON con kind Event y apiVersion audit.k8s.io/v1; trae el nivel RequestResponse, la etapa ResponseComplete, el verbo create, el objectRef con resource secrets, namespace la-porteria y name libro-de-minuta, y el bloque user con username kubernetes-admin y groups kubeadm:cluster-admins y system:authenticated. Trae además dos campos que justifican la lectura completa: requestObject y responseObject, con el cuerpo del Secret, es decir la clave que acaba de guardar, en base64, escrita para siempre en un archivo de texto. La política que el API server tiene montada lo explica: hay una regla con level RequestResponse para los Secrets y una regla final con level Metadata para todo lo demás. Las banderas con las que se abrió la minuta son --audit-policy-file=/etc/kubernetes/audit/policy.yaml y --audit-log-path=/var/log/kubernetes/audit/audit.log, más las tres de rotación.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 14: La película del que entró de madrugada (10 pts)

En la bodega del conjunto se perdió la combinación de la caja fuerte, y el administrador quiere saber quién fue. No hay testigos, no hay cámaras en esa esquina y el celador de turno jura que no vio a nadie. Lo único que hay es la minuta, que en este clúster lleva prendida desde el primer minuto.

Usted no va a preguntarle a nadie. En una investigación seria los testimonios se contrastan contra el registro, y no al revés; el Capítulo 14 armó la película en ese orden: primero quién pidió qué, después con qué resultado y, solo al final, quién era esa identidad. La bitácora de auditoría le da las tres cosas en el mismo archivo, y lo que usted debe aprender aquí es a ordenarlas por hora y a leerlas como una secuencia, no como eventos sueltos.

Un detalle vale el paso entero, y está escondido en un código de respuesta. La cuenta que se llevó el secreto lo intentó antes y no pudo. Ese primer intento fallido es la parte más útil de toda la película, porque dice dos cosas: que la cuenta ya existía y estaba buscando, y que algo cambió entre ese momento y el siguiente. Busque qué cambió en medio. Está anotado, con nombre propio, entre los dos intentos.

Hay una segunda lección, más incómoda. Como la política de este clúster anota los Secrets en nivel RequestResponse, el evento del intento exitoso no dice solo "leyó la caja fuerte": trae adentro lo que la caja fuerte contenía. La minuta que sirve para investigar es también un archivo de texto con secretos adentro, en base64, que es decir en claro. No es un defecto de este laboratorio, es la consecuencia real de ese nivel, y por eso la contención de este paso no termina con revocar un permiso.

Queda la tentación, que en este paso viene disfrazada de diligencia: borrar la cuenta comprometida. Se siente responsable y se ve limpio, pero con eso usted destruye la única identidad que amarra la película. Lo que hay que quitar es el permiso, no el sujeto. La comprobación exige que la cuenta siga ahí, que ya no pueda leer Secrets, que la otra cuenta del namespace siga trabajando con normalidad y que el valor del secreto ya no sea el que quedó escrito en la bitácora.

ENTREGABLE: el namespace `la-bodega` contenido, es decir la cuenta comprometida todavía presente pero sin poder leer Secrets, la otra cuenta trabajando igual que antes y el Secret `la-caja-fuerte` con un valor nuevo; y el archivo `~/cks-lab/p06/02-respuesta.txt`, exactamente 5 líneas:

```text
CUENTA=<el username completo, tal como lo escribe la minuta, de la identidad que leyó el Secret>
SECRETO=<el nombre del Secret que se llevó>
CODIGO_PRIMER_INTENTO=<el código de respuesta del primer intento de esa cuenta sobre ese Secret>
ROLEBINDING=<el nombre del RoleBinding que se creó entre el primer intento y el segundo>
VALOR_FILTRADO=<el valor de la llave clave del Secret, ya decodificado, tal como quedó en la bitácora>
```

<details>
<summary>Qué debería ver</summary>

La película del namespace la-bodega sale ordenada por hora y se lee sola. Primero kubernetes-admin crea el Secret la-caja-fuerte (nivel RequestResponse, código 201), el ConfigMap inventario, la cuenta auxiliar-de-dia, un Role de solo ConfigMaps y su RoleBinding turno-de-dia. Después pide un token para auxiliar-de-dia (create serviceaccounts con subresource token) y esa cuenta lee el ConfigMap: 200, todo normal, es el turno de día haciendo su trabajo. Luego aparece la cuenta auxiliar-de-turno: le sacan token, intenta listar Pods y recibe 403, e intenta leer el Secret la-caja-fuerte y también recibe 403. Menos de una décima de segundo después, kubernetes-admin crea el Role llaves-de-la-caja y el RoleBinding prestamo-de-llaves, y unos tres segundos más tarde aparece el mismo get sobre el mismo Secret por la misma cuenta, ahora con código 200 (corrida del 2026-10-11). Ese par 403 y luego 200 con un RoleBinding en medio es el incidente. Como los Secrets se anotan en RequestResponse, el evento del 200 trae responseObject.data.clave en base64: al decodificarlo sale combinacion-7431-de-la-caja-fuerte, que es lo que se llevaron. Después de contener, kubectl auth can-i contesta no para esa cuenta y el Secret queda con un valor distinto.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 13: La cámara que solo graba si hay alguien sentado (10 pts)

El conjunto por fin puso cámaras, y el primer mes fue una maravilla: se acabaron los problemas del estacionamiento. El segundo mes empezaron las quejas, porque la cámara del sótano no había grabado nada la noche en que se metieron al depósito. El técnico vino, la revisó y dijo la frase más honesta de todo el asunto: "es que esa cámara solo graba cuando detecta a alguien sentado en el puesto de vigilancia".

Algo parecido le va a pasar en este paso, y es a propósito. Falco está corriendo, está viendo llamadas al sistema por eBPF moderno, y la regla canónica que le interesa se llama Terminal shell in container. Usted entrará a un contenedor con kubectl exec, correrá algo y la alerta no saldrá. El Pod está bien, Falco está bien, la regla está puesta. Y no suena.

La cámara no está dañada: la condición de la regla pide algo que su exec no le está dando. El Capítulo 13 insistió en esto: una regla de detección es una expresión, y una expresión no se adivina, se lee. Falco trae sus reglas en un archivo de texto dentro de su propio contenedor, y esa condición tiene cinco términos unidos por and. Cuatro se cumplen con cualquier exec. El quinto es el que la mantiene callada.

Su trabajo es leer la condición, entender cuál de los cinco términos falta, aportarlo, y después encontrar la alerta y amarrarla al Pod correcto. Amarrarla no es opcional: Falco corre privilegiado y con hostPID, o sea que ve las llamadas al sistema de toda la máquina, incluidos contenedores que nada tienen que ver con este laboratorio. Quedarse con "salió una alerta de esa regla" no prueba nada. Hay que llegar hasta el id del contenedor y confirmar que es el del Pod del ejercicio.

Y la advertencia, que en seguridad es la más cara de todas: una regla que molesta se puede apagar. Se pone enabled false en un archivo de rules.d y se acabó el ruido. La comprobación de este paso dispara una alerta nueva por su cuenta en otro Pod y exige verla llegar, precisamente para que apagar la regla no se parezca a resolver el ejercicio.

ENTREGABLE: la alerta provocada sobre el Pod `porteria` del namespace `la-celaduria`, con el DaemonSet de Falco todavía prendido y la regla todavía activa; y el archivo `~/cks-lab/p06/03-respuesta.txt`, exactamente 4 líneas:

```text
REGLA=<el nombre de la regla que disparó, tal como Falco lo escribe>
PRIORIDAD=<la prioridad de esa alerta, tal como Falco la escribe>
CAMPO_QUE_EXIGE_TERMINAL=<el campo de la condición de la regla que un exec normal no satisface, escrito tal cual aparece en la condición, sin el operador ni el valor>
CONTENEDOR=<el id de contenedor de doce caracteres que trae la alerta, sin el prefijo containerd://>
```

<details>
<summary>Qué debería ver</summary>

El DaemonSet falco aparece con 1 deseado y 1 listo, y las primeras líneas de su registro dicen `Falco version: 0.44.1` y listan los archivos de configuración que validó. La regla, leída en /etc/falco/falco_rules.yaml, tiene una condición de cinco términos unidos por and (spawned_process, container, shell_procs, proc.tty != 0 y container_entrypoint), más una exclusión por excepciones definidas por el usuario. El primer exec, el normal, no genera ninguna alerta nueva: el contador no se mueve (en la corrida del 2026-10-11 marcaba 1, la alerta de la sonda del montaje), y ese silencio es el diagnóstico. El segundo exec, el que pide terminal, sí dispara, y la alerta sale con rule Terminal shell in container, priority Notice, el campo output_fields["container.id"] con doce caracteres hexadecimales y proc.cmdline con el comando que usted corrió. Ese id de doce caracteres es el prefijo del containerID que kubectl reporta para el Pod `porteria`, que viene con el prefijo containerd:// por delante. Vale notar que la propia descripción de la regla recomienda correlacionarla con los registros de auditoría de exec, que es lo que usted hizo en el Paso 1 y repetirá en el Paso 4.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 15: El local que no se deja remodelar a mitad de turno (10 pts)

El local de la esquina cambia de forma cada quince días. Un mes le tumban una pared, al otro le abren una ventana al callejón, y el dueño lo cuenta orgulloso, como si fuera dinamismo. Al final se lo robaron por la ventana que abrieron para "que entrara más luz", y el celador ni se enteró porque llevaba tres meses viendo entrar y salir obreros con herramientas.

El problema no fue la ventana, sino que el local se podía remodelar a mitad de turno. El Capítulo 15 lo planteó así: un contenedor que se puede modificar mientras corre es un contenedor donde alguien puede dejar algo plantado, y la respuesta es `readOnlyRootFilesystem`. Con eso, el sistema de archivos raíz del contenedor deja de aceptar escrituras, y todo lo que el atacante quiera sembrar se le cae de las manos.

La parte difícil es otra, y por eso este paso existe. Poner el candado es una línea. Lograr que el negocio siga vendiendo con el candado puesto es el trabajo real. La `caja-registradora` de este laboratorio escribe en dos sitios cuando arranca, y con la raíz de solo lectura muere en el primer intento. La solución no es quitar el candado ni complicar la imagen: es montar `emptyDir` justo donde la aplicación necesita escribir, y en ningún otro lado. Superficie escribible mínima. Un cajón para trabajar, no una bodega.

Hay dos atajos, ambos cómodos. El primero es montarle un cajón a `/tmp` "por si acaso": eso le devuelve al atacante el directorio donde suele dejarse lo que se descarga. La comprobación prueba `/tmp` a mano y exige que siga sin aceptar escrituras. El segundo es conseguir el espacio con un `hostPath`: eso no hace inmutable el contenedor, le abre una puerta al nodo, y la comprobación cuenta los `hostPath` y exige cero.

Una última cosa, que amarra este paso con el Paso 1. Usted va a entrar al contenedor con `kubectl exec` para probar el candado. Esa entrada queda anotada en la misma minuta de la portería, con el recurso, el subrecurso, el verbo, el nivel y, además, el comando que usted corrió adentro. La descripción de la regla de Falco del Paso 3 lo recomienda: cuando la cámara muestra un shell dentro de un contenedor, la minuta dice qué identidad lo abrió. Cámara y minuta no compiten, se completan.

ENTREGABLE: el Deployment `caja-registradora` del namespace `el-local` corriendo con `readOnlyRootFilesystem` en true, con cajones `emptyDir` solo donde la aplicación los necesita, atendiendo 200 por su Service; y el archivo `~/cks-lab/p06/04-respuesta.txt`, exactamente 5 líneas:

```text
RECURSO=<el recurso que la minuta anota para un kubectl exec>
SUBRECURSO=<el subrecurso que la minuta anota para un kubectl exec>
VERBO=<el verbo que su minuta anotó para ese exec>
NIVEL=<el nivel de auditoría de ese evento>
ETAPAS=<las dos etapas que ese mismo exec dejó anotadas, en orden cronológico, separadas por una coma y sin espacios>
```

<details>
<summary>Qué debería ver</summary>

Antes del candado el contenedor escribe donde quiere: /www/index.html y /var/log/local/ventas.log existen y los creó el propio comando de arranque. Tras el parche el rollout termina y el Pod nuevo queda 1/1, pero solo porque los dos cajones están puestos: si se pone readOnlyRootFilesystem sin montar nada, el contenedor muere en el primer mkdir con Read-only file system y el Deployment queda dando vueltas. Con los cajones puestos, la prueba desde adentro sale así: touch /www/prueba funciona, touch /tmp/prueba contesta touch: /tmp/prueba: Read-only file system, touch /prueba contesta lo mismo, y el archivo de ventas conserva la línea de apertura del turno. La llamada al Service desde el Pod mandadero devuelve 200. Y la minuta trae, por cada kubectl exec que usted hizo, dos eventos con el mismo requestReceivedTimestamp: uno en etapa ResponseStarted y otro en ResponseComplete, ambos con resource pods, subresource exec, nivel Metadata y el nombre del Pod. El verbo depende del transporte de su kubectl: con kubectl cliente v1.37.0 (corrida del 2026-10-11), que negocia WebSocket, queda anotado como get. Y el requestURI trae el comando completo que usted corrió, con URL-encoding y todo, de modo que la minuta no solo dice que usted entró: dice qué hizo adentro.

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

- **Síntoma (step 1):** El comando minuta me contesta 'Error: No such container' o no imprime nada
  **Qué hacer:** La bitácora vive dentro del nodo del clúster, no en su disco, porque el API server corre ahí y el archivo pertenece a root. El atajo `~/cks-lab/p06/bin/minuta` entra al contenedor cks-p06-control-plane con docker exec y le hace cat al archivo. Si el contenedor no existe, el clúster desapareció: corra el teardown y el montaje otra vez. Si existe y el archivo está vacío, el API server arrancó sin la bandera de auditoría, algo que el montaje habría detenido con `ERROR SONDA-MINUTA-MUDA`; lo más probable es que alguien haya truncado el archivo después.

- **Síntoma (step 1):** Escribí `GRUPO=system:masters` porque así aparece en los ejemplos y la comprobación me lo rechaza
  **Qué hacer:** Ese es el punto del paso. system:masters es el grupo del certificado de emergencia, y kubeadm hace años que no se lo pone al kubeconfig de administrador de uso diario: le pone un grupo propio, atado a un ClusterRoleBinding con el ClusterRole cluster-admin. La minuta se lo dice en el campo user.groups del evento y, en el campo annotations, deja escrito con nombre propio cuál ClusterRoleBinding autorizó la petición. Léalo del evento, no de la memoria.

- **Síntoma (step 2):** Revoqué el permiso y kubectl auth can-i me sigue contestando yes
  **Qué hacer:** Un permiso en RBAC son dos objetos: el Role, que dice qué se puede hacer, y el RoleBinding, que dice a quién. Borrar uno de los dos basta para cortar el acceso, pero solo si borró el que ata a esa cuenta. Confirme con kubectl -n la-bodega get rolebindings -o wide, que muestra el sujeto de cada uno, y recuerde que un ClusterRoleBinding también puede estar dando ese permiso desde fuera del namespace. La respuesta autoritativa es siempre kubectl auth can-i con --as, porque le pregunta al autorizador y no a su lectura de los manifiestos.

- **Síntoma (step 2):** No encuentro el valor filtrado: el evento del get no trae requestObject
  **Qué hacer:** Y no lo traerá nunca, porque una petición get no envía cuerpo: lo que busca es responseObject, que es lo que el API server devolvió. Ahí dentro está data.clave en base64, y hay que decodificarlo. Si tampoco ve responseObject, está mirando el evento de la etapa ResponseStarted o el intento que falló con 403, que no devolvió nada. Filtre por responseStatus.code igual a 200.

- **Síntoma (step 3):** kubectl exec -it me dice que no puede usar una terminal porque no estoy en una sesión interactiva
  **Qué hacer:** kubectl -t solo reserva una terminal en el contenedor si su propio proceso tiene una. Desde una terminal normal, kubectl exec -it basta. Desde un script, un pipeline o un editor sin terminal hay que pedírsela a script(1), una herramienta de util-linux hecha para eso: script -q -c "<su comando kubectl exec -it>" /dev/null. Así lo hace el montaje de este laboratorio y así lo hace la comprobación.

- **Síntoma (step 3):** El archivo de cámaras está lleno de alertas Drop and execute new binary in container que yo no provoqué
  **Qué hacer:** Son reales y no son suyas. Esa regla dispara cuando un proceso ejecuta un binario que no venía en la imagen base, y el kubelet, los complementos de red y cualquier otro contenedor de su máquina pueden hacerlo en cualquier momento. Falco está viendo el kernel entero, no solo este clúster. Filtre siempre por el nombre de la regla que le interesa y después por el id de contenedor, que es lo que hace la comprobación. En un clúster de producción, ese ruido es el trabajo que hay que hacer antes de que un detector de tiempo de ejecución sea útil: afinar.

- **Síntoma (step 4):** Puse readOnlyRootFilesystem y el Pod entra en CrashLoopBackOff
  **Qué hacer:** Es lo que tiene que pasar antes de montar los cajones, y es la mitad del ejercicio. Lea el registro del contenedor con kubectl -n el-local logs <pod> y verá el primer sitio donde no pudo escribir, con el mensaje Read-only file system. Monte un emptyDir ahí, vuelva a intentar y repita hasta que arranque. No adivine la lista de directorios: la aplicación le dice uno por uno cuál le falta. Si prefiere adelantarse, lea el campo command del Deployment, donde están escritas todas las escrituras del arranque.

- **Síntoma (step 4):** Mi minuta anota el exec con verbo create y el laboratorio dice que a él le salió get
  **Qué hacer:** Los dos son correctos, y por eso esa línea del entregable se califica contra su bitácora y no contra una constante. El verbo depende del transporte que negocie su cliente: el kubectl moderno usa WebSocket, que es una petición GET con actualización de protocolo, y por eso queda anotado como get; el transporte SPDY antiguo usaba POST y quedaba como create. Si usted forzó el transporte antiguo con la variable de entorno correspondiente, verá create y estará bien. Escriba lo que diga su evento.

## Para ir más lejos

- Vuelva al Paso 1 y cambie la política de auditoría: agregue una regla con level None para el usuario kubernetes-admin, antes de la regla de los Secrets. Vuelva a crear el clúster, repita la acción del Paso 1 y observe que la minuta queda muda para su propio usuario. Escriba tres líneas sobre por qué un atacante que llega al nodo prefiere editar la política antes que borrar el archivo de la bitácora, y sobre qué control de los Capítulos 1 a 4 le habría estorbado para hacerlo.
- En el Paso 2, mida el costo del nivel RequestResponse. Cambie la política para que los ConfigMaps también queden en RequestResponse, vuelva a crear el clúster, corra algo que genere tráfico y compare el tamaño del archivo de auditoría a los cinco minutos con el que produce este laboratorio. Después decida, por escrito, qué recursos dejaría en ese nivel en un clúster de producción y cuáles no, sabiendo que el nivel que da la evidencia es el mismo que pone los secretos en un archivo de texto.
- En el Paso 3, escriba su propia regla de Falco en /etc/falco/rules.d en vez de usar una de las que vienen. Por ejemplo, una que dispare cuando alguien lea /etc/shadow dentro de un contenedor, que a diferencia de la del ejercicio no necesita terminal. Compárela con la regla canónica y anote qué campos tuvo que usar. Escribir una regla es una buena forma de entender por qué la del ejercicio pedía proc.tty.
- En el Paso 4, suba un escalón: además del sistema de archivos raíz de solo lectura, haga que el contenedor corra como un usuario que no sea root, con runAsNonRoot y runAsUser, y con allowPrivilegeEscalation en false. Observe qué se rompe primero y por qué, y arregle solo lo que haga falta. Después compare su Pod con lo que exige el perfil restricted de los Pod Security Standards y anote qué le falta todavía.
- Junte los cuatro pasos en un solo ejercicio de correlación, que es lo que se hace en un incidente real: dispare la alerta del Paso 3 sobre el Pod del Paso 4 y después, usando solo la hora de la alerta, encuentre en la minuta el evento de exec que la produjo y la identidad que lo abrió. Escriba la línea de tiempo completa. Falco dice qué pasó dentro del contenedor; la auditoría dice quién lo pidió desde afuera. Ninguna de las dos, sola, cierra el caso.

## Referencias

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
