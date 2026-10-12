# Parte II - Laboratorio: un carné al que le quitan la llave maestra, un celador que hace la ronda sin llevar llaves encima, una reja que volvió a pedir cédula, y el reglamento de admisión que alguien había descolgado de la pared

- Tiempo: 55 min
- Puntos: 40

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solo el objetivo y el entregable, y la secuencia de comandos que lo resuelve vive en el campo cmd de ese paso, para que usted la revele después de haberlo intentado con sus propias manos. El Paso 1 le entrega una ServiceAccount a la que alguien, para salir del paso un viernes, le amarró cluster-admin dentro del namespace, y le pide dejarla solo con los permisos que la aplicación usa; la calificación pregunta con kubectl auth can-i por los dos lados, exige yes en lo que tiene que poder y no en una lista larga de cosas que no, y por eso volver a poner cluster-admin no es un atajo sino la forma más rápida de perder el paso. El Paso 2 le pide apagar el montaje automático del token de la ServiceAccount para una pareja de cuenta y Pod, y demostrarlo desde adentro del contenedor: la carpeta del token no puede existir, la cuenta tiene que seguir siendo la misma, y la aplicación tiene que seguir trabajando mientras la califican. El Paso 3 baja al nodo: el kubelet de este clúster quedó atendiendo peticiones sin credenciales en el puerto 10250, y a usted le toca cerrarlo y probarlo, midiendo la configuración viva del kubelet en vez de creerle a un archivo, con el nodo todavía Ready y el API server todavía capaz de hablarle. El Paso 4 cierra con el plano de control: alguien le quitó NodeRestriction a la lista de plugins de admisión del kube-apiserver, y usted tiene que auditarla, devolverla y demostrar que el plugin está haciendo cumplir algo, no solo apareciendo en una bandera.

## Prerrequisitos

- Una máquina Linux con kind, kubectl y docker en el PATH, acceso a internet, y al menos 4 GB de RAM libre. Este laboratorio crea su propio clúster de kind llamado cks-p02, de un solo nodo, y lo borra al final. Todo lo que hace pasa por un kubeconfig privado en ~/cks-lab/p02/kubeconfig, que se pasa con --kubeconfig en cada comando: su kubeconfig de siempre nunca se toca, su contexto actual nunca cambia, y ningún otro clúster suyo se ve afectado. No ejecute este laboratorio contra un clúster de producción, porque los Pasos 3 y 4 modifican el kubelet y el kube-apiserver del nodo.
- Ejecutado y verificado el 2026-10-11 en la máquina de pruebas con kind v0.33.0, cliente de kubectl v1.37.0 y Docker 29.9.0, imagen de nodo kindest/node:v1.34.2 fijada por digest sha256:745f8ed46d8e99517774768227fd1a0af34a6bf395aef9c7ed98fbce0e263918 (la línea 1.34 es la del currículo de CKS que este libro acompaña), y la imagen de carga de trabajo busybox:1.37.0 fijada por digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Confirme su kind con kind version y su kubectl con kubectl version --client antes de empezar, en vez de creerle a este párrafo.
- El script de setup no se limita a construir el clúster: le hace cuatro pruebas antes de dejarlo empezar, porque los cuatro pasos dan por hecho comportamientos que un clúster puede aceptar por API y no aplicar en la práctica. Comprueba que RBAC niegue lo que no está autorizado, que el token de la ServiceAccount se monte solo cuando nadie lo prohíbe, que la negación de la etiqueta restringida venga de NodeRestriction y de ningún otro control, y que el kubelet de este nodo autenticara antes de romperlo y quede abierto después. Si alguna falla, el setup imprime un error con nombre propio y se detiene, porque un laboratorio que califica un control que nadie aplica es decoración.
- El setup deja dos fallas de endurecimiento puestas a propósito en el plano de control de este clúster, y las aplica como cargas útiles en base64 para que usted no pueda leer la avería en el script y salga a copiar la respuesta. No es un secreto criptográfico, es una venda de cortesía: si quiere, las decodifica en diez segundos, y la clave de respuestas está en el campo cmd de cada paso. El punto es que usted audite el clúster que tiene enfrente, que es lo que le van a pedir en el examen y en el trabajo.
- Haber leído los Capítulos 3 y 4. Este laboratorio no vuelve a explicar qué es un Role, en qué se diferencia de un ClusterRole, qué es una ServiceAccount ni qué es un plugin de admisión; le hace operar las cuatro cosas contra un clúster real y las califica contra su estado real. Tenga presente que los Pasos 3 y 4 reinician componentes del plano de control: si acaba de tocar el kubelet o el kube-apiserver, déle al clúster medio minuto antes de volver a calificar cualquier paso.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 3: Al carné del celador le sobraban llaves, y se las vamos a quitar una por una (10 pts)

El Capítulo 3 se lo dijo con el carné del celador: la ServiceAccount dice quién es, el Role dice qué se puede hacer, y el RoleBinding es el acto de entregarle ese permiso a ese carné. Aquí le toca vivir la parte fea, que es la que se encuentra uno en los clústeres de verdad: llegar a una portería donde alguien ya repartió las llaves y nadie se acuerda por qué.

Lo que pasa es que en el namespace `porteria` hay un RoleBinding llamado llave-maestra-del-celador, y su roleRef apunta a cluster-admin. Eso no fue un ataque, eso fue un viernes a las seis de la tarde: la aplicación de la garita empezó a fallar con 403, alguien buscó en internet, la primera respuesta que encontró funcionó de una, y ahí quedó. La garita usa dos permisos y tiene todos.

La herramienta que le va a salvar el examen es kubectl auth can-i con --as. Le deja preguntarle al API server, sin desplegar nada y sin esperar a que algo se caiga, si una identidad concreta puede hacer una acción concreta. Úsela por los dos lados siempre: pregunte por lo que tiene que poder y pregunte por lo que no tiene que poder. Un permiso probado solo por el lado positivo no está probado, está supuesto.

Hay un detalle que en el examen se paga caro: get, list y watch son tres verbos distintos, y es fácil juntarlos en la cabeza porque kubectl get los usa casi juntos. Pedir la colección entera es list. Quedarse escuchando cambios es watch. Si su aplicación no escucha cambios, watch no va en el Role, y la calificación de este paso le va a preguntar precisamente por ese renglón.

Volver a amarrar cluster-admin no es una solución rápida, es la renuncia al modelo entero. Un contenedor comprometido con ese carné puesto lee todos los Secrets del namespace en la primera línea de su script, y usted se enteró tres semanas después. Si le tienta pensar que este laboratorio exagera, mire el 403 del Secret desde adentro del Pod y piense cuántos contenedores de su trabajo harían esa misma llamada y recibirían un 200.

ENTREGABLE: la ServiceAccount `celador-de-turno` intacta, sin cluster-admin por ningún lado, solo con permisos de get, list y watch sobre pods y de get y list sobre configmaps dentro del namespace `porteria`; el Pod `garita` todavía corriendo con ese carné puesto; y el archivo `~/cks-lab/p02/01-respuesta.txt`, exactamente 5 líneas:

```text
CUENTA_DE_LA_GARITA=<el nombre de la ServiceAccount que el Pod garita declara>
PUEDE_LISTAR_PODS=<lo que responde kubectl auth can-i list pods para ese carné en `porteria`>
PUEDE_BORRAR_PODS=<lo que responde kubectl auth can-i delete pods para ese carné en `porteria`>
PUEDE_LEER_SECRETS=<lo que responde kubectl auth can-i get secrets para ese carné en `porteria`>
CODIGO_EN_LOS_SECRETS=<el código HTTP que devuelve el API server cuando el Pod garita pide el Secret clave-de-la-reja con su token>
```

<details>
<summary>Qué debería ver</summary>

El primer comando le muestra el tamaño del problema en cinco líneas: el roleRef del RoleBinding dice kind ClusterRole y name cluster-admin, o sea que dentro de este namespace ese carné puede hacerlo todo. Al borrarlo, kubectl responde `rolebinding.rbac.authorization.k8s.io "llave-maestra-del-celador" deleted from porteria namespace`. Después el Role y el RoleBinding nuevos se crean sin ruido, y las nueve preguntas de auth can-i responden, en orden: yes para list pods, yes para watch pods, yes para get configmaps, no para watch configmaps, no para delete pods, no para get secrets, no para create pods, no para list pods en kube-system, y no para la pregunta comodín de todo en todos lados. Fíjese en el cuarto renglón, que es el que más fácil se pasa por alto: get y list sobre los ConfigMaps sí, watch no, porque watch es un verbo aparte y la aplicación no lo usa. Desde adentro del Pod garita, las tres llamadas al API server con el token proyectado devuelven HTTP/1.1 200 para la lista de Pods, HTTP/1.1 200 para el ConfigMap turnos-del-mes, y HTTP/1.1 403 para el Secret clave-de-la-reja. Cada llamada se reintenta hasta tres veces si la primera no devuelve código. Ese 403 es el que hay que mirar despacio: no es que el celador no encuentre la clave de la reja, es que el API server sabe quién está preguntando y le dice que no.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 3: El celador hace la ronda sin llevar ni una llave en el bolsillo (10 pts)

El Capítulo 3 terminó con la frase que da nombre a la mitad de este laboratorio: hay llaves que no se prestan. Y en Kubernetes la llave que más se presta sin que nadie la pida es el token de la ServiceAccount, porque se monta solo. Usted crea un Pod, no escribe nada sobre cuentas ni sobre tokens, y adentro del contenedor aparece una carpeta con un ca.crt, un namespace y un token que habla con el API server.

Ese montaje fue un default de comodidad de hace muchos años y hoy es lo primero que busca cualquiera que logre ejecutar un comando dentro de un contenedor suyo. No necesita romper nada: lee un archivo. Si esa cuenta tiene permisos de sobra, ahí se acabó el conjunto. Es habitual que una aplicación nunca le hable al API server: sirve una página, procesa una cola o escribe en una base de datos.

Por eso el celador de la ronda nocturna sale sin llaves. El campo se llama automountServiceAccountToken y se puede escribir en dos sitios: en la ServiceAccount, donde marca el default para todos los Pods que la usen, y en el spec del Pod, donde manda sobre el anterior. La práctica que se pide en el examen y en cualquier revisión seria es ponerlo en los dos: la cuenta cierra por defecto y el Pod lo confirma, de modo que si mañana alguien edita la cuenta, el Pod no se abre solo.

Hay un detalle operativo que suele costar el primer intento: ese campo del Pod no se puede cambiar en caliente. El spec de un Pod es casi todo inmutable, así que aquí no hay kubectl edit que valga; toca borrar el Pod y volverlo a crear con el campo puesto. En un Deployment usted edita la plantilla y el controlador hace el reemplazo por usted, pero el mecanismo de fondo es el mismo: un Pod nuevo.

Hay un atajo que no sirve: cambiarle la cuenta al Pod para que la carpeta desaparezca no es apagar el montaje, es cambiar de identidad. La cuenta default también monta token, así que ni siquiera funcionaría; y si funcionara, usted habría resuelto el síntoma dejando la cuenta original tan abierta como estaba. Quitar la llave es quitar la llave, no cambiar de celador.

ENTREGABLE: la ServiceAccount `celador-sin-llaves` con automountServiceAccountToken en false, el Pod `ronda-nocturna` corriendo con esa misma cuenta y con automountServiceAccountToken en false en su propio spec, sin ninguna carpeta de token adentro del contenedor, y con su bitácora `/tmp/ronda.log` todavía creciendo. Además el archivo `~/cks-lab/p02/02-respuesta.txt`, exactamente 4 líneas:

```text
AUTOMOUNT_EN_LA_CUENTA=<el valor del campo automountServiceAccountToken en la ServiceAccount>
AUTOMOUNT_EN_EL_POD=<el valor del mismo campo en el spec del Pod>
CARPETA_DEL_TOKEN=<escriba EXISTE o NO_EXISTE según lo que encuentre adentro del contenedor>
CUENTA_DE_LA_RONDA=<el nombre de la ServiceAccount que el Pod declara>
```

<details>
<summary>Qué debería ver</summary>

El primer ls, hecho antes de tocar nada, imprime tres nombres dentro de la carpeta del token: ca.crt, namespace y token. Esos tres archivos aparecieron solos, sin que nadie los pidiera, y ese es el punto del paso. El grep sobre la ServiceAccount no encuentra nada y por eso se imprime la línea entre paréntesis: cuando el campo automountServiceAccountToken no está escrito, el valor efectivo es montar. Después del patch y de recrear el Pod, el ls falla con ls: /var/run/secrets/kubernetes.io/serviceaccount: No such file or directory y detrás sale la línea (no hay carpeta de token); no es que la carpeta esté vacía, es que no existe. El jsonpath imprime cuenta=celador-sin-llaves y automount_del_pod=false, que son las dos cosas que la calificación va a leer. Y los dos wc -l separados por ocho segundos devuelven dos números distintos, el segundo mayor que el primero (en la ejecución del 2026-10-11, 1 y 3), con el tail mostrando marcas de tiempo recientes: la ronda sigue trabajando sin llaves encima, que es la mitad del paso que se suele olvidar.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 4: La reja del conjunto estaba abriéndole a cualquiera que timbrara (10 pts)

El Capítulo 4 le habló de la reja eléctrica del conjunto: esa que abre sola, que todos usan y que nadie revisa hasta el día en que abre cuando no debe. En un clúster de Kubernetes esa reja se llama kubelet y atiende en el puerto 10250 de cada nodo.

El kubelet no es un detalle de infraestructura: es la única cosa del clúster que puede ejecutar comandos adentro de sus contenedores, leerle los logs a cualquier Pod y contarle a quien pregunte todo lo que está corriendo en la máquina. Si esa puerta atiende sin pedir cédula, no importa cuánto RBAC haya escrito arriba: el atacante no pasa por el API server, le habla directo al nodo.

Y aquí hay dos controles distintos que es fácil confundir. El primero es la autenticación: quién dice ser usted. Cuando el acceso anónimo está habilitado, cualquiera que timbre entra con el nombre system:anonymous. El segundo es la autorización: qué puede hacer una vez adentro. Cuando el modo es AlwaysAllow, el kubelet dice que sí a todo sin preguntarle a nadie. El modo Webhook es el bueno, porque el kubelet le consulta al API server con un SubjectAccessReview antes de cada petición. Los dos tienen que estar como toca; arreglar uno solo deja la mitad del hueco abierto.

Hay una tercera cosa que conviene mirar de una vez porque en el examen la preguntan: el readOnlyPort, el puerto 10255, que servía métricas y estado sin ninguna autenticación. En este nodo viene apagado de fábrica, y la sonda de este paso lo confirma en vez de darlo por hecho. Esa es la costumbre que le queremos dejar: medir, no suponer.

Hay un atajo que conviene nombrar antes de que se le ocurra: apagar el kubelet no es cerrar la reja, es tumbar la reja. La sonda deja de contestar, sí, pero el nodo se pone NotReady y sus Pods se quedan sin nadie que los cuide. Lo mismo con bloquear el puerto por firewall: se ve parecido desde afuera y por dentro es otra cosa. Cerrar bien significa que el kubelet siga trabajando, que el API server le siga llegando, y que el desconocido reciba un 401 en la cara.

ENTREGABLE: el kubelet de este nodo con el acceso anónimo deshabilitado y el modo de autorización en Webhook, verificado en la configuración viva y no solo en el archivo; el nodo todavía Ready; los Pods `garita` y `ronda-nocturna` todavía Running; y el archivo `~/cks-lab/p02/03-respuesta.txt`, exactamente 4 líneas:

```text
CODIGO_SIN_CREDENCIALES=<el código HTTP que devuelve https://127.0.0.1:10250/pods desde adentro del nodo, sin credenciales>
ANONIMO_HABILITADO=<el valor de authentication.anonymous.enabled en la configuración viva del kubelet>
MODO_DE_AUTORIZACION=<el valor de authorization.mode en la configuración viva del kubelet>
ARCHIVO_DE_CONFIGURACION=<la ruta absoluta del archivo de configuración que el proceso kubelet tiene declarado en su línea de comandos>
```

<details>
<summary>Qué debería ver</summary>

La primera línea es la que duele: sin_credenciales=200. Una petición sin ningún certificado ni token le acaba de sacar al kubelet la lista de Pods del nodo. La lectura de la configuración viva confirma por qué: "anonymous":{"enabled":true} y "authorization":{"mode":"AlwaysAllow", que son las dos mitades del problema, una que deja entrar sin cédula y otra que después dice que sí a todo. La tercera línea le dice de dónde saca el kubelet esa configuración, y en este nodo imprime --config=/var/lib/kubelet/config.yaml. Después del arreglo y del reinicio, el nodo vuelve a Ready, los dos Pods vuelven a Ready, y la misma petición imprime sin_credenciales=401: el kubelet ya no responde nada a quien no se identifica. La sonda al puerto de solo lectura imprime puerto_de_solo_lectura=000, que no es un código HTTP sino la forma en que curl le dice que ahí no hay nadie escuchando, y eso es lo correcto: en este nodo el readOnlyPort viene apagado. La configuración viva ahora dice "anonymous":{"enabled":false} y "authorization":{"mode":"Webhook", y el exec al Pod garita imprime su mensaje, que es la prueba de que usted cerró la reja para los desconocidos y no para el API server. Si el exec le contesta pod does not exist, no es una falla: el kubelet acaba de reiniciar y todavía no ha vuelto a sincronizar la lista de Pods. En la ejecución del 2026-10-11 el primer intento dio ese error y el segundo imprimió el mensaje; el bucle del comando ya repite el intento.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 4: El reglamento de admisión estaba descolgado de la pared de la administración (10 pts)

El Capítulo 4 le contó que la administración del conjunto tiene un reglamento colgado en la pared, y que ese reglamento no sirve de nada guardado en un cajón. En Kubernetes ese reglamento son los plugins de admisión del kube-apiserver: código que se mete entre la autenticación y el guardado en etcd, y que puede rechazar, cambiar o dejar pasar cada objeto que entra al clúster.

La lista de plugins habilitados se declara en una bandera de la línea de comandos del kube-apiserver, --enable-admission-plugins, y en un clúster armado con kubeadm ese comando vive en un archivo de Pod estático adentro del nodo. Es decir que auditar esto no es un kubectl get: hay que ir a mirar el manifiesto y, mejor todavía, la línea de comandos del proceso en ejecución, porque el archivo y el proceso pueden discrepar.

El plugin que a usted le toca hoy es NodeRestriction, y su trabajo es limitar lo que un kubelet puede hacerle a su propio objeto Node. Sin él, un nodo comprometido puede editarse etiquetas para atraer cargas de trabajo que no le tocaban, entre otras cosas más entretenidas. Con él, hay un conjunto de etiquetas que el nodo simplemente no puede tocar, y en este laboratorio usted lo va a comprobar con etiquetas del prefijo node-restriction.kubernetes.io/, que existen precisamente para eso: para etiquetar nodos de un modo que el propio nodo no pueda falsificar.

La forma de comprobarlo es la que vale la pena aprender. No se trata de leer la bandera y creerle: se trata de hacerse pasar por la identidad del kubelet del nodo, con --as y --as-group, intentar la acción prohibida, y ver la negación con sus ojos. Esa técnica sirve para cualquier control de admisión que usted quiera auditar, no solo para este.

Este paso esconde un atajo de otra clase, el más limpio del laboratorio: usted podría conseguir que la etiqueta sea rechazada sin prender el plugin, simplemente rompiéndole los permisos al nodo. La negación se vería parecida y usted diría misión cumplida. Por eso la calificación, después de exigir la negación, pone una etiqueta corriente con la misma identidad y exige que esa sí pase. Si las dos fallan, usted no endureció el clúster: lo averió.

ENTREGABLE: el kube-apiserver de este nodo corriendo con NodeRestriction en la lista de --enable-admission-plugins, el mismo plugin presente en el manifiesto de Pod estático que hay en disco, el clúster sano (nodo Ready, /healthz en ok, los dos Pods de la portería Running), y el archivo `~/cks-lab/p02/04-respuesta.txt`, exactamente 4 líneas:

```text
BANDERA_DE_ADMISION=<el nombre exacto de la bandera del kube-apiserver que enumera los plugins de admisión habilitados, con sus dos guiones>
PLUGINS_HABILITADOS=<el valor vivo de esa bandera, tal cual, sin el nombre de la bandera>
ARCHIVO_DEL_MANIFIESTO=<la ruta absoluta del manifiesto de Pod estático del kube-apiserver dentro del nodo>
RESPUESTA_A_LA_ETIQUETA=<la palabra que trae entre paréntesis el error del API server cuando el nodo intenta ponerse una etiqueta node-restriction.kubernetes.io/>
```

<details>
<summary>Qué debería ver</summary>

La primera línea es el hallazgo de la auditoría: la bandera viva dice "--enable-admission-plugins=LimitRanger". No está vacía, y por eso es tan fácil pasarla de largo leyendo por encima: hay una lista de plugins, se ve poblada, y lo que falta es justamente el que importa. El staticPodPath sale como "staticPodPath":"/etc/kubernetes/manifests", que es donde el kubelet de este nodo busca los manifiestos estáticos, y el grep confirma la misma bandera en la línea 19 del archivo kube-apiserver.yaml. La prueba antes del arreglo es contundente: el primer intento de ponerle al nodo una etiqueta con prefijo node-restriction.kubernetes.io/ suplantando al propio kubelet imprime node/cks-p02-control-plane labeled, o sea que pasó. Después de corregir el manifiesto, el kube-apiserver se reinicia solo (el kubelet vigila esa carpeta) y en unos veinte segundos la bandera viva imprime bandera viva: --enable-admission-plugins=NodeRestriction, con /healthz respondiendo ok. Y el mismo intento de etiqueta ahora responde Error from server (Forbidden): nodes "cks-p02-control-plane" is forbidden: is not allowed to modify labels: node-restriction.kubernetes.io/prueba, mientras que la etiqueta corriente ejemplo.com/prueba sí se aplica y devuelve node/cks-p02-control-plane labeled. Ese contraste es el paso entero: la misma identidad, dos etiquetas, una negada y la otra permitida, y la diferencia la puso el plugin de admisión.

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

- **Síntoma (step 1):** auth can-i responde no para list pods aunque el Role y el RoleBinding ya existen
  **Qué hacer:** La causa más frecuente es que el RoleBinding apunte al sujeto equivocado. Un sujeto de tipo ServiceAccount necesita su namespace además de su nombre, y si se le olvida el namespace el binding queda apuntando a una cuenta que no existe, sin dar ningún error. Mire el sujeto real con `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get rolebinding el-celador-solo-mira -o yaml` y confirme que diga kind ServiceAccount, name celador-de-turno y namespace `porteria`. Otra causa posible es que el roleRef apunte a un ClusterRole cuando usted creó un Role, o al revés: el roleRef es inmutable, así que si está mal hay que borrar el RoleBinding y crearlo otra vez. Y revise que está preguntando con el nombre completo de la identidad, `system:serviceaccount:porteria:celador-de-turno`, porque --as=celador-de-turno pregunta por un usuario que no existe.

- **Síntoma (step 1):** Las preguntas de auth can-i salen bien pero el Pod garita sigue recibiendo 403 al listar Pods
  **Qué hacer:** Hay dos causas y conviene descartarlas en orden. La primera es que el Pod no esté usando el carné que usted arregló: confirme con `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get pod garita -o jsonpath='{.spec.serviceAccountName}'` que dice celador-de-turno y no default, porque el campo no se puede cambiar en un Pod vivo y toca recrearlo. La segunda es que el token que el contenedor tiene montado sea de antes del cambio; los tokens proyectados se renuevan solos, pero si acaba de recrear objetos, vuelva a leer el archivo del token dentro del contenedor en vez de reutilizar una variable vieja de su shell. Para ver quién cree el API server que está preguntando, use `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig auth whoami --as=system:serviceaccount:porteria:celador-de-turno`.

- **Síntoma (step 2):** kubectl edit sobre el Pod contesta que el campo automountServiceAccountToken no se puede cambiar
  **Qué hacer:** No es un error suyo: el spec de un Pod es inmutable salvo un puñado de campos (la imagen del contenedor, activeDeadlineSeconds y las tolerations, según la documentación de la API). automountServiceAccountToken no está en esa lista, así que la única salida es borrar el Pod y crearlo otra vez con el campo puesto. Use el manifiesto que el setup le dejó en ~/cks-lab/p02/ronda-nocturna.yaml, añádale la línea automountServiceAccountToken: false al mismo nivel que serviceAccountName, borre el Pod con `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria delete pod ronda-nocturna --now` y vuelva a aplicarlo. Si esto fuera un Deployment, usted editaría la plantilla y el controlador haría el reemplazo, pero por debajo también sería un Pod nuevo.

- **Síntoma (step 2):** La carpeta del token desapareció pero la comprobación sigue fallando
  **Qué hacer:** Repase las tres exigencias que no son la carpeta. Primera, el campo en la ServiceAccount: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get sa celador-sin-llaves -o jsonpath='{.automountServiceAccountToken}'` tiene que imprimir false, y si imprime vacío es que solo lo puso en el Pod. Segunda, la cuenta del Pod: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria get pod ronda-nocturna -o jsonpath='{.spec.serviceAccountName}'` tiene que decir celador-sin-llaves. Tercera, y es fácil olvidarla, la bitácora: `kubectl --kubeconfig ~/cks-lab/p02/kubeconfig -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log'` tiene que dar un número que crece si lo pide dos veces con unos segundos de por medio. Si al recrear el Pod le cambió el comando por un sleep, la ronda dejó de trabajar y el paso falla aunque el token ya no esté.

- **Síntoma (step 3):** Se editó /var/lib/kubelet/config.yaml pero /configz sigue mostrando los valores viejos
  **Qué hacer:** El kubelet lee ese archivo al arrancar, no en caliente, así que el archivo y el proceso pueden estar diciendo cosas distintas y esa diferencia es lo que este paso mide. Reinicie el servicio con docker exec cks-p02-control-plane systemctl restart kubelet y espere a que el nodo vuelva a Ready con kubectl --kubeconfig ~/cks-lab/p02/kubeconfig wait --for=condition=Ready node/cks-p02-control-plane --timeout=180s. Si después del reinicio el nodo no vuelve, lo más probable es un error de indentación en el YAML que acaba de editar: mírelo con docker exec cks-p02-control-plane journalctl -u kubelet -n 40 --no-pager, que le va a decir en qué línea se atoró.

- **Síntoma (step 3):** La sonda devuelve 403 en vez de 401 y la comprobación falla
  **Qué hacer:** Ese 403 le está diciendo algo preciso: el kubelet sí dejó entrar a la petición anónima y quien la frenó fue la autorización, no la autenticación. O sea que usted arregló authorization.mode pero dejó authentication.anonymous.enabled en true. Confirme leyendo la configuración viva con kubectl --kubeconfig ~/cks-lab/p02/kubeconfig get --raw /api/v1/nodes/cks-p02-control-plane/proxy/configz | tr ',' '\n' | grep -i anonymous, ponga ese campo en false en el archivo de configuración del kubelet, reinicie el servicio y vuelva a sondear. Vale la pena que compare los dos códigos una vez con calma, porque distinguir 401 de 403 en una sonda es una de las lecturas que más rápido le dice qué control está fallando.

- **Síntoma (step 4):** Se editó el manifiesto pero la bandera viva del kube-apiserver sigue mostrando el valor viejo
  **Qué hacer:** Un Pod estático no se aplica con kubectl: lo vigila el kubelet, que mira la carpeta declarada en staticPodPath y recrea el contenedor cuando el archivo cambia. Ese ciclo tarda del orden de veinte segundos en este clúster, así que lo primero es esperar. Si pasado un minuto la bandera no cambia, mire si el contenedor está reiniciándose en bucle con docker exec cks-p02-control-plane crictl ps -a | grep apiserver y lea el motivo con docker exec cks-p02-control-plane crictl logs $(docker exec cks-p02-control-plane crictl ps -a -q --name kube-apiserver | head -1). Un nombre de plugin mal escrito hace que el kube-apiserver no arranque, y entonces usted se queda sin API server para consultar por qué no arrancó, que es la razón por la que este archivo se edita despacio.

- **Síntoma (step 4):** kubectl deja de responder del todo después de tocar el manifiesto del kube-apiserver
  **Qué hacer:** Es el escenario que este paso quiere que usted viva una vez en un clúster desechable y nunca más en uno de verdad. El API server no arrancó, y como kubectl habla con el API server, se quedó sin herramientas. La salida es siempre por el nodo, no por kubectl: entre con docker exec -it cks-p02-control-plane bash, mire el archivo con less /etc/kubernetes/manifests/kube-apiserver.yaml y corrija lo que escribió mal. Si no encuentra el error a simple vista, revise los logs del contenedor con crictl logs, y si de plano quiere volver al punto de partida, el laboratorio es desechable: borre el clúster con kind delete cluster --name cks-p02 y vuelva a correr el setup. La costumbre que vale la pena llevarse es hacer una copia del manifiesto antes de tocarlo.

## Para ir más lejos

- Vuelva al Paso 1 y reemplace el Role de namespace por un ClusterRole con las mismas reglas, amarrado con un RoleBinding dentro del namespace `porteria`. Vuelva a correr la comprobación: pasa, porque se califica el estado final. Ahora cambie ese RoleBinding por un ClusterRoleBinding y vuelva a correrla: falla, y no por un capricho del enunciado sino porque el mismo ClusterRole atado de esa otra forma acaba de abrirle kube-system al celador. Ese par de experimentos le deja grabada la diferencia entre el rol y el amarre, que es una de las distinciones centrales de RBAC.
- Cree un tercer Pod en el namespace `porteria` que use la ServiceAccount celador-sin-llaves y no diga nada sobre automountServiceAccountToken en su propio spec. Entre y mire si tiene carpeta de token. Después ponga el campo en true solo en ese Pod, recréelo y vuelva a mirar. Con esos dos intentos usted acaba de comprobar en la práctica la regla de precedencia: el spec del Pod manda sobre el default de la cuenta, en los dos sentidos, y por eso la recomendación de escribirlo en los dos sitios no es redundancia sino cierre.
- Con el kubelet ya endurecido, intente la misma sonda del Paso 3 pero autenticándose bien: saque el certificado de cliente que el kube-apiserver usa para hablarle al kubelet, que en este nodo vive en /etc/kubernetes/pki, y repita la llamada a https://127.0.0.1:10250/pods pasándolo con --cert y --key. Ahora sí le va a contestar la lista de Pods. Ese ejercicio le muestra que endurecer el kubelet no fue cerrar el puerto, fue exigirle cédula a quien timbra, y de paso le deja claro por qué ese certificado del plano de control merece el mismo cuidado que una llave de la caja fuerte.
- Añádale al kube-apiserver un segundo plugin de admisión de la lista oficial junto a NodeRestriction, por ejemplo NamespaceLifecycle, separándolos con una coma, y compruebe que el Paso 4 sigue pasando. Después intente una combinación imposible poniendo el mismo nombre en --enable-admission-plugins y en --disable-admission-plugins al tiempo, y observe qué hace el kube-apiserver al arrancar. Haga ese segundo experimento sabiendo que va a tener que entrar por el nodo a arreglarlo, que es la práctica que le queremos dejar antes de que le toque en un clúster que le importe.

## Referencias

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
