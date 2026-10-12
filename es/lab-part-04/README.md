# Parte IV - Laboratorio: un reglamento que sí se hace cumplir en la portería, una caja fuerte que se abre por dentro de etcd para ver qué guardó, un empleado de uniforme que igual hace el turno, y un citófono que no le abre a quien no tenga carné

- Tiempo: 55 min
- Puntos: 40

## Objetivo

Este es un laboratorio Exam-Style: cada paso le da el objetivo y el entregable, nunca el comando, y la secuencia que lo resuelve vive en el campo cmd de ese paso para que usted la revele cuando ya lo haya intentado con sus propias manos. El Paso 1 le entrega una torre cuyo reglamento de convivencia está en el nivel flojo y un manifiesto de inquilino que la portería rechaza; usted tiene que subir el reglamento a restricted y hacer que el inquilino quepa en él, y la calificación no se conforma con ver el Pod corriendo: vuelve a medir la portería en vivo intentando meter dos Pods que restricted tiene que rechazar, de modo que bajar el nivel a baseline o a privileged para que todo pase pierde el paso. El Paso 2 abre la caja fuerte de la tienda por el lado que nadie mira: usted crea un Secret y un ConfigMap con el mismo texto adentro y va a leer los dos en crudo desde etcd, en el nodo del plano de control, para comprobar con sus propios ojos que del Secret no sale texto plano y del ConfigMap sí; la calificación crea su propio Secret de prueba en el momento de calificar y lo lee otra vez desde etcd, así que apagar el cifrado del clúster para que algo funcione hace fallar el paso. El Paso 3 le pone el uniforme obligatorio: un Pod que no corre como root, con la raíz del sistema de archivos en solo lectura, sin una sola capability, y que aun así sigue escribiendo su archivo de turno cada dos segundos; la calificación no lee el YAML y ya, entra al contenedor vivo a preguntarle al proceso quién es, qué capabilities le quedaron y si puede escribir en la raíz. El Paso 4 cierra con el citófono del Capítulo 9: el servidor TLS del conjunto hoy le contesta a cualquiera, y usted tiene que exigirle carné de vecino; la calificación mide las tres llamadas que importan, sin carné, con un carné firmado por otra CA y con el carné bueno, y exige que las dos primeras no den 200 y la tercera sí, porque esa es la única forma honesta de probar que la verificación sigue puesta.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker y openssl en el PATH, acceso a internet para descargar las imágenes, y al menos 4 GB de RAM libre. Este laboratorio crea su propio clúster de kind llamado cks-p04, de un solo nodo, y lo borra al final. Todo pasa por un kubeconfig privado en ~/cks-lab/p04/kubeconfig, que se pasa con --kubeconfig en cada comando: su kubeconfig de siempre nunca se toca, su contexto actual nunca cambia, y ningún otro clúster suyo se ve afectado. No ejecute este laboratorio contra un clúster de producción.
- Versiones con las que este laboratorio se ejecutó completo el 2026-10-11: kind v0.33.0, kubectl cliente v1.37.0, Docker 29.9.0, OpenSSL 3.0.13. Imagen de nodo kindest/node:v1.36.1 fijada por digest sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5, imagen de carga de trabajo busybox:1.37.0 por digest sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0, servidor nginx:1.29.3-alpine por digest sha256:b3c656d55d7ad751196f21b7fd2e8d4da9cb430e32f646adcf92441b72f82b14 y cliente curlimages/curl:8.19.0 por digest sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c. El binario etcdctl no se descarga de internet: se saca de la propia imagen de etcd que ya vive en el nodo, que en esta imagen de kind es registry.k8s.io/etcd:3.6.8-0. Confirme su kind con kind version y su kubectl con kubectl version --client en vez de creerle a este párrafo.
- El clúster nace con el cifrado de Secrets en reposo ya configurado, y eso es deliberado. El setup genera una clave nueva de 32 bytes en su propia máquina, escribe una EncryptionConfiguration en ~/cks-lab/p04/enc/enc.yaml, monta ese directorio dentro del nodo y le pasa --encryption-provider-config al kube-apiserver a través de kubeadmConfigPatches. La clave se genera en cada instalación y nunca se versiona: si usted borra el workspace, la clave se va con él y el clúster viejo ya no puede leer sus propios Secrets, que es lo que pasa en la vida real cuando alguien pierde la llave de la caja.
- El setup no se limita a construir el clúster: le hace cuatro pruebas de sustrato antes de dejarlo empezar, porque los cuatro pasos dan por hecho comportamientos que un clúster puede aceptar por API y no aplicar en la práctica. Comprueba que Pod Security Admission rechace lo que restricted prohíbe (y que baseline sí lo dejaba pasar, para que la diferencia sea medida y no afirmada), que un Secret recién creado quede cifrado en etcd, que el kubelet haga cumplir readOnlyRootFilesystem y el drop de todas las capabilities, y que el citófono TLS responda por la red del clúster. Si alguna falla, el setup imprime un error con nombre propio y se detiene, porque un laboratorio que califica un control que nadie aplica es decoración.
- Haber leído los Capítulos 7, 8 y 9. Este laboratorio no vuelve a explicar los tres niveles de Pod Security Standards, la diferencia entre codificar en base64 y cifrar, ni por qué un citófono sin autenticación mutua no aísla nada; le hace operar las tres cosas contra un clúster real y las califica contra su estado real.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 7: El reglamento de la torre A sube a restricted, y el inquilino tiene que caber en él (10 pts)

El Capítulo 7 le explicó que el reglamento de convivencia del conjunto tiene tres niveles y que lo que importa no es tenerlo pegado en la cartelera, sino que la portería lo haga cumplir. Aquí le toca vivirlo: la torre A tiene el reglamento puesto en el nivel de la mitad, alguien le dejó un manifiesto de inquilino listo para aplicar, usted lo aplica confiado, y la portería se lo devuelve en la cara.

Lo que pasa es que ese rechazo no es un capricho. El mensaje que devuelve Pod Security Admission es de los más generosos que da Kubernetes porque le dice tres cosas de una: qué nivel estaba aplicando, qué versión de ese nivel, y cuál campo del Pod rompió cuál regla. Léalo entero antes de tocar nada, porque cuando usted suba el reglamento a restricted el mensaje cambia y le entrega la lista completa del uniforme que falta.

Un punto que se paga caro el día del examen: Pod Security Admission es admisión, o sea que actúa en el momento en que el objeto entra, y solamente ahí. Si usted etiqueta un namespace donde ya hay Pods violando el nivel nuevo, esos Pods se quedan corriendo sin problema y lo único que recibe es un warning en la consola. La etiqueta no desaloja a nadie. Por eso subir el nivel de un namespace vivo no es una acción de limpieza, es una acción de contención hacia adelante.

La salida fácil no es aflojar el reglamento. Bajar la etiqueta enforce a baseline, bajarla a privileged o borrarla hace que el inquilino entre en tres segundos y hace que usted repruebe, porque el inquilino entró pero la torre se quedó sin portería. La calificación no le cree a la etiqueta: en el momento de calificar mete dos Pods de prueba propios, uno corriente y uno privilegiado, y los dos tienen que rebotar. Si rebotan, el reglamento existe; si pasan, usted lo desarmó.

ENTREGABLE: la etiqueta `pod-security.kubernetes.io/enforce` del namespace `torre-a` en `restricted`, la etiqueta `pod-security.kubernetes.io/enforce-version` presente y no vacía, el Pod `inquilino` corriendo y Ready en ese namespace sin `privileged`, y el archivo `~/cks-lab/p04/01-respuesta.txt`, exactamente 2 líneas:

```text
NIVEL_APLICADO=<el nivel que quedó en la etiqueta enforce del namespace torre-a>
USUARIO_DEL_INQUILINO=<el uid con el que corre el proceso, leído desde adentro del contenedor>
```

<details>
<summary>Qué debería ver</summary>

El primer apply, con la torre todavía en baseline, se estrella y el error nombra la regla rota: Error from server (Forbidden): error when creating "inquilino.yaml": pods "inquilino" is forbidden: violates PodSecurity "baseline:latest": privileged (container "inquilino" must not set securityContext.privileged=true). Después de subir la etiqueta a restricted, el mismo manifiesto vuelve a fallar pero ahora el mensaje dice violates PodSecurity "restricted:latest" y trae cinco reglas rotas en vez de una: la misma privileged de antes, más allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true y seccompProfile. Esas cuatro nuevas son el uniforme que le falta al inquilino: lo que restricted exige y baseline no exigía. Con el manifiesto arreglado, el apply crea el Pod, el wait devuelve pod/inquilino condition met, el jsonpath imprime nivel=restricted y versión=latest, y el exec imprime 1000, que es el uid que usted eligió y no el 0 que traía la imagen. Si usted eligió otro uid distinto de cero, ese número es el suyo y es el que va en el archivo de respuesta.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 8: La caja fuerte de la tienda, abierta por dentro de etcd (10 pts)

El Capítulo 8 le dijo que la caja fuerte de la tienda no es tan fuerte como suena. Aquí la abre usted mismo, pero no por la puerta de adelante, que es kubectl get secret, sino por detrás: entrando al nodo del plano de control y leyendo etcd directamente, que es lo que haría alguien que se robó el disco.

Este clúster nació con el cifrado en reposo ya puesto. No se lo van a poner en el examen así de servido, pero para lo que importa hoy sirve mejor, porque le permite hacer la comparación que enseña: guarde el mismo texto en un Secret y en un ConfigMap, y vaya a ver cuál de los dos aparece legible en el disco del nodo. La EncryptionConfiguration de esta máquina cubre secrets y no cubre configmaps, y esa lista de recursos es una decisión que alguien tomó y que usted puede leer en el archivo montado.

Y hay un detalle de plomería que le va a costar diez minutos si no lo sabe: etcdctl no viene instalado en la imagen del nodo de kind. El contenedor de etcd es distroless y no tiene shell, así que no se entra ahí a buscarlo. Pero la imagen de etcd sí vive en el almacén de containerd del nodo, y el nodo sí tiene ctr, de modo que el binario se saca de la imagen sin bajar nada de internet. El setup ya se lo dejó puesto en /usr/local/bin/etcdctl para que usted no gaste el turno en eso, pero sepa de dónde salió.

Una confusión que conviene despejar: base64 no es cifrado. Cuando usted hace kubectl get secret -o yaml y ve una cadena de caracteres raros, eso es codificación, se deshace con un comando de una línea y no protege nada. Lo único que hace la diferencia entre un Secret y un ConfigMap frente a alguien que tenga el disco del nodo es que exista una EncryptionConfiguration cubriendo ese recurso. Sin ella, las dos cosas son texto plano en el disco y la única diferencia real que queda es quién puede leerlas por RBAC.

ENTREGABLE: el Secret `caja-fuerte` y el ConfigMap `aviso-de-la-tienda` en el namespace `tienda`, los dos con la llave `clave` y el valor exacto `la-plata-de-la-tienda-2026`, y el archivo `~/cks-lab/p04/02-respuesta.txt`, exactamente 3 líneas:

```text
SECRETO_CIFRADO_EN_ETCD=<true si la lectura cruda del Secret no muestra el valor en claro, false si lo muestra>
CONFIGMAP_EN_CLARO_EN_ETCD=<true si la lectura cruda del ConfigMap sí muestra el valor en claro, false si no>
PREFIJO_DEL_PROVEEDOR=<el prefijo completo, con sus dos puntos finales, que antecede al texto cifrado del Secret en etcd>
```

<details>
<summary>Qué debería ver</summary>

El grep sobre el manifiesto del kube-apiserver imprime la línea 43 con --encryption-provider-config=/etc/kubernetes/enc/enc.yaml, que es la prueba de que el parche de kubeadm quedó puesto desde el nacimiento del clúster. El cat del archivo montado muestra la EncryptionConfiguration con un proveedor aescbc cuya llave se llama llave-de-la-caja y un proveedor identity de respaldo detrás. La lectura cruda del Secret imprime la clave /registry/secrets/tienda/caja-fuerte y, en la línea siguiente, texto que empieza por k8s:enc:aescbc:v1:llave-de-la-caja: y sigue con basura binaria: eso es texto cifrado y no hay forma de leer la clave ahí. La lectura cruda del ConfigMap imprime en cambio protobuf legible donde se ve clave seguido de la-plata-de-la-tienda-2026 en texto plano, sin ningún adorno. Los tres greps finales imprimen k8s:enc:aescbc:v1:llave-de-la-caja:, después 0 (el texto de la clave no aparece ni una vez en el volcado del Secret) y después 1 (sí aparece en el del ConfigMap). Esa asimetría es todo el Capítulo 8 en tres líneas: la EncryptionConfiguration de este clúster cubre secrets y no cubre configmaps, y lo que usted meta en el objeto equivocado se guarda tal cual en el disco del nodo.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 7: El uniforme obligatorio, y el empleado que igual hace el turno (10 pts)

El Capítulo 7 le presentó los campos del reglamento uno por uno. Este paso los pone a trabajar juntos y le hace la única pregunta que importa después de endurecer algo: ¿y sigue funcionando?

El uniforme obligatorio son tres prendas y cada una tapa una vía de ataque distinta. No correr como root le quita al proceso la identidad que le permitiría tocar cualquier cosa si se sale del contenedor. La raíz en solo lectura le impide dejar un binario, un cron o una biblioteca modificada dentro de la imagen, que es el paso siguiente clásico después de una ejecución remota. Y soltar todas las capabilities le quita hasta los permisos raros que el runtime regala por costumbre y que su aplicación no necesita.

La tercera prenda es fácil de poner mal, y no por difícil sino por descuidada. Cuando usted monta la raíz en solo lectura, la aplicación que escribía en /tmp deja de arrancar, y la reacción refleja es quitar la prenda. La reacción correcta es la contraria: darle a la aplicación un sitio donde sí pueda escribir, montado aparte, y dejar la raíz cerrada. Un emptyDir montado en /tmp cuesta tres líneas y le da a la aplicación su sitio de escritura. Esa técnica, la de la sonda en /tmp, es la que separa un Pod endurecido de un Pod apagado.

Este paso se puede perder por los dos lados. Si usted afloja el uniforme para que el empleado trabaje, pierde. Si usted deja el uniforme perfecto pero el empleado se queda quieto, también pierde, porque la calificación mira el archivo de turno dos veces con cinco segundos de diferencia y exige que la hora haya cambiado. Endurecer no es apagar. Un contenedor endurecido que ya no hace nada es un incidente con mejor prensa.

ENTREGABLE: el Pod `empleado` corriendo y Ready en el namespace `apartamento-303`, con una imagen busybox, que no corre como root, con la raíz del sistema de archivos en solo lectura, con todas las capabilities soltadas, y que escribe la hora en `/tmp/turno.txt` cada dos segundos sin parar. Y el archivo `~/cks-lab/p04/03-respuesta.txt`, exactamente 3 líneas:

```text
UID_DEL_PROCESO=<el uid que reporta id -u adentro del contenedor>
CAPEFF_DEL_PROCESO=<el valor de CapEff que reporta /proc/1/status adentro del contenedor, tal cual, con todos sus ceros>
ESCRITURA_EN_LA_RAIZ=<denegada o permitida, según lo que le pase al intentar crear un archivo en la raíz>
```

<details>
<summary>Qué debería ver</summary>

El Pod arranca y queda Ready. El id -u imprime 1000, o el uid distinto de cero que usted haya elegido. El grep de CapEff imprime CapEff: 0000000000000000, es decir dieciséis ceros: al proceso no le quedó ni una capability, ni siquiera las que Docker deja por defecto. El touch en la raíz falla con touch: /prueba-en-la-raiz: Read-only file system y termina con salida=1. El grep de /proc/mounts muestra dos líneas que explican por qué el Pod sigue trabajando: la raíz aparece como overlay / overlay ro,relatime,... y /tmp aparece como un sistema de archivos aparte montado rw. Los dos cat imprimen fechas distintas separadas por unos segundos, porque el bucle sigue escribiendo su archivo de turno en el único sitio donde puede. Ese es el punto entero del paso: la raíz en solo lectura no es un candado que apaga la aplicación, es un candado que la obliga a decir en voz alta dónde necesita escribir.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 9: El citófono que no le abre a quien no tenga carné (10 pts)

El Capítulo 9 terminó con el citófono cifrado, y aquí es donde se ve que cifrado no quiere decir seguro. El citófono del conjunto ya habla TLS: el tráfico entre el vecino y el servidor va cifrado y nadie que esté escuchando en el pasillo lo entiende. Y aun así, hoy le abre a cualquiera que toque, porque cifrar la conversación y saber con quién está hablando son dos problemas distintos.

En TLS normal el que presenta cédula es el servidor, no el cliente. Por eso su navegador sabe que está hablando con el banco, pero el banco no sabe que es usted hasta que usted se registra por dentro. Mutual TLS es simplemente exigir la cédula por los dos lados: el servidor sigue presentando la suya y además le pide una al cliente, firmada por una CA que él reconozca. En el conjunto eso es el carné de residente: usted no entra porque el citófono suene bonito, entra porque el celador reconoce quién firmó su carné.

Aquí no hay malla de servicios ni sidecars, y eso es a propósito: este paso se califica midiendo tres llamadas, no leyendo la documentación de un producto. Y hay una medida fácil de pasar por alto, la que prueba que la verificación existe: presentar un carné bien hecho pero firmado por otra CA. Un servidor mal configurado, de esos que piden certificado pero no lo validan contra ninguna autoridad, le abre a ese carné falso igual que al bueno, y quien solo probó "sin carné da error, con carné da bien" se va creyendo que aisló algo.

Apagar el citófono no es cerrarlo. Borrar el Pod del servidor hace que la llamada sin carné falle, sí, pero la llamada con carné también falla, y un citófono que no le contesta ni al residente no es una medida de seguridad, es un daño. Lo mismo con poner ssl_verify_client en optional para que deje de dar error: eso es escribir la palabra sin hacer la cosa. La calificación mide las tres llamadas y además lee la configuración viva adentro del contenedor, así que la palabra tiene que estar y la cosa tiene que pasar.

ENTREGABLE: el citófono exigiendo certificado de cliente validado contra la CA del conjunto, con los Pods `citofono` y `vecino` los dos en Running, y el saludo del servidor mostrando el CN del certificado que presentó el cliente. Y el archivo `~/cks-lab/p04/04-respuesta.txt`, exactamente 3 líneas:

```text
SIN_CARNET=<el código HTTP de una llamada al citófono sin presentar certificado de cliente>
CARNET_DE_LA_CALLE=<el código HTTP de una llamada presentando el certificado firmado por la CA de la calle>
CON_CARNET=<el código HTTP de una llamada presentando el carné del vecino>
```

<details>
<summary>Qué debería ver</summary>

Antes de tocar nada, la primera llamada al citófono devolvía 200 sin presentar ningún carné, que es lo que el setup ya le había dicho: el citófono existe, habla TLS y le abre a cualquiera. Después de exigir carné y recrear el Pod, las tres medidas cambian a sin_carnet=400, carnet_de_la_calle=400 y carnet_del_vecino=200. Las dos primeras salen 400 y no 403 ni un fallo de conexión porque el handshake TLS sí se completa y es nginx el que después contesta con Bad Request y el cuerpo No required SSL certificate was sent; fíjese en que curl termina con salida cero en ese caso, así que mirar el código de salida de curl no le sirve para calificar nada y por eso se mide el código HTTP. La última llamada imprime el cuerpo citofono del 303: adelante, CN=apartamento-303, y ese CN no lo escribió usted: nginx lo sacó del certificado que el cliente presentó, lo cual demuestra que el servidor no solo pidió el carné sino que lo leyó y lo validó contra la CA del conjunto. En la máquina donde se ejecutó este laboratorio la propagación del endpoint del Service tardó unos segundos tras recrear el Pod; si la primera medida le sale 000, espere y repita.

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

- **Síntoma (step 1):** El Pod es rechazado con runAsNonRoot != true aunque usted ya puso runAsNonRoot: true
  **Qué hacer:** Mire dónde lo puso. El securityContext del Pod y el securityContext del contenedor son dos objetos distintos con campos distintos, y varios campos existen solo en uno de los dos. runAsNonRoot, runAsUser y seccompProfile viven en los dos niveles, pero allowPrivilegeEscalation y capabilities existen únicamente en el del contenedor. Si el rechazo persiste, revise el mensaje completo: nombra el contenedor entre comillas justo antes de la regla rota, y eso le dice si le está hablando al Pod o a un contenedor concreto. La referencia de campos está en https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

- **Síntoma (step 1):** El Pod se admite pero se queda en CreateContainerConfigError y nunca arranca
  **Qué hacer:** Ese ya no es un problema de admisión sino del kubelet: usted puso runAsNonRoot en true pero no dijo con cuál uid correr, y la imagen no declara un usuario no root. El API server admite el Pod porque el campo está bien puesto; el kubelet, al ir a arrancar el contenedor, descubre que la imagen quiere correr como uid 0 y se niega. Lea el motivo textual con kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n torre-a describe pod inquilino y añada un runAsUser distinto de cero.

- **Síntoma (step 2):** etcdctl responde context deadline exceeded o no devuelve nada
  **Qué hacer:** Hay dos causas posibles. O le faltó decirle a qué endpoint hablarle y a qué certificados presentarle: etcd de kubeadm escucha en https://127.0.0.1:2379 y exige certificado de cliente, y los que sirven están en /etc/kubernetes/pki/etcd/ dentro del nodo. O la ruta de la llave está mal escrita: en etcd los objetos de Kubernetes viven bajo /registry/<recurso en plural>/<namespace>/<nombre>, así que un Secret llamado caja-fuerte del namespace tienda está en /registry/secrets/tienda/caja-fuerte y no en /registry/secret/... Si duda de la ruta, liste las llaves con un prefijo y --keys-only en vez de adivinar. El procedimiento completo está en https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/

- **Síntoma (step 2):** El volcado del Secret sale lleno de caracteres de control y la terminal se desconfigura
  **Qué hacer:** Es texto cifrado, o sea bytes binarios, y es lo que se esperaba: la terminal está intentando interpretarlos como escapes. Páselo por cat -v para verlos como secuencias imprimibles, o hágale grep en vez de mirarlo entero, que es lo que necesita de todas formas: grep -oa para sacar el prefijo y grep -ca para contar cuántas veces aparece el texto en claro. La bandera -a es la que le dice a grep que trate un archivo binario como texto; sin ella grep le contesta Binary file matches y usted no ve nada.

- **Síntoma (step 3):** El contenedor entra en CrashLoopBackOff apenas usted pone readOnlyRootFilesystem en true
  **Qué hacer:** La aplicación está intentando escribir en algún sitio de la imagen y ahora no puede. La respuesta no es quitar la bandera sino averiguar dónde escribe y montarle ahí un volumen escribible. Mire los logs del contenedor que se cayó con kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n apartamento-303 logs empleado --previous: el error indica la ruta en la que intentó escribir. Después monte un emptyDir en esa ruta. Si son varias rutas, monte varios emptyDir; sigue siendo más seguro que abrir la imagen entera.

- **Síntoma (step 3):** CapEff no queda en ceros aunque usted puso drop ALL
  **Qué hacer:** Revise dos cosas. Primero, dónde puso capabilities: ese campo existe solamente en el securityContext del contenedor, nunca en el del Pod, y si lo escribe en el del Pod el API server se lo rechaza o lo ignora según la versión. Segundo, si dejó un add al lado del drop: la lista de add se aplica después de la de drop, así que drop ALL más add NET_BIND_SERVICE deja esa capability puesta y CapEff no sale en ceros. Y tercero, revise que esté leyendo /proc/1/status y no /proc/self/status desde un exec: el proceso del exec puede tener un conjunto distinto al proceso principal del contenedor.

- **Síntoma (step 4):** Usted cambió el ConfigMap pero el citófono sigue abriéndole a cualquiera
  **Qué hacer:** El archivo del citófono está montado con subPath, y un montaje con subPath nunca se actualiza cuando el ConfigMap cambia. Esa es una decisión de diseño de Kubernetes, no un bug: el kubelet solo refresca el contenido de un volumen de ConfigMap montado como directorio. Además, aunque el archivo se refrescara, nginx lee su configuración al arrancar. Las dos cosas se resuelven igual: borre el Pod del servidor y vuelva a crearlo desde el manifiesto que el setup le dejó en ~/cks-lab/p04/citofono-pod.yaml. Verifique que la configuración viva cambió con kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono exec citofono -- cat /etc/nginx/conf.d/citofono.conf antes de volver a medir.

- **Síntoma (step 4):** Las tres llamadas devuelven 000 y curl dice que no se pudo conectar
  **Qué hacer:** El código 000 de curl no es un código HTTP: significa que nunca hubo respuesta. Después de borrar y recrear el Pod del servidor, el Service necesita unos segundos para volver a apuntar al Pod nuevo, y mientras tanto las llamadas fallan a nivel de conexión. Compruebe a quién apunta ahora el Service con kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono get endpointslices y repita cuando aparezca una dirección. Si el endpoint aparece y aun así no conecta, mire si nginx arrancó: kubectl --kubeconfig ~/cks-lab/p04/kubeconfig -n citofono logs citofono, porque un error de sintaxis en la configuración hace que el contenedor se caiga en vez de servir.

## Para ir más lejos

- Vuelva al Paso 1 y en vez de subir el nivel de un solo namespace, ponga las etiquetas de Pod Security Admission en modo warn y audit en todos los namespaces del clúster sin poner enforce en ninguno, y después cree Pods que violen restricted. Va a ver que le llegan advertencias en la consola y entradas en el registro de auditoría sin que nada se bloquee. Esa es la forma real de subir el nivel en un clúster con inquilinos: primero se mide quién se rompería, después se aplica. Compare cuántos Pods de kube-system violarían restricted y saque su propia conclusión sobre por qué el nivel no se sube de una.
- Vuelva al Paso 2 y rote la llave. Añada una segunda llave al proveedor aescbc de la EncryptionConfiguration, póngala de primera, deje el kube-apiserver recogerla, y lea otra vez el Secret caja-fuerte desde etcd: va a seguir cifrado con la llave vieja, porque rotar la llave no reescribe lo que ya estaba guardado. Después haga que se reescriba y compruebe que el prefijo cambió de nombre de llave. Ese paso es fácil de olvidar cuando toca rotar de verdad, y es la diferencia entre creer que rotó y haber rotado.
- Vuelva al Paso 4 y cambie ssl_verify_client de on a optional_no_ca, recree el Pod y vuelva a hacer las tres llamadas. Va a ver que el carné firmado por la CA de la calle ahora entra igual que el bueno, y que la llamada sin carné sigue fallando: la configuración pide certificado pero no lo valida contra nadie. Guarde los tres códigos y compárelos con los del paso calificado. Es una configuración que se presenta como mTLS y que no aísla nada.

## Referencias

- Kubernetes Project, Pod Security Admission. Primary source for the pod-security.kubernetes.io/enforce and enforce-version labels Step 1 sets, for the fact that the controller acts only at admission and never evicts running Pods, and for the shape of the violates PodSecurity rejection message the step reads. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Kubernetes Project, Pod Security Standards. Primary source for the exact field list the restricted level demands and the baseline level does not (allowPrivilegeEscalation, capabilities drop ALL, runAsNonRoot, seccompProfile), which is what makes Step 1's before-and-after rejection messages differ. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Kubernetes Project, Encrypting Confidential Data at Rest. Primary source for the EncryptionConfiguration file format the setup writes, for the --encryption-provider-config flag passed through kubeadm, for the resource list semantics that make secrets covered and configmaps not, and for the etcdctl verification recipe with the k8s:enc: prefix that Step 2 executes. Verified 2026-08-21. https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
- Kubernetes Project, Configure a Security Context for a Pod or Container. Primary source for runAsNonRoot, runAsUser, readOnlyRootFilesystem and capabilities, and for which of those fields exist on the Pod's securityContext versus the container's, which is where Step 3's field-placement errors come from. Verified 2026-08-21. https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Kubernetes Project, Security Checklist. Primary source for the cluster-level hardening items this lab exercises hands-on: Pod Security Standards enforcement per namespace, encryption of Secrets at rest, and the recommendation to terminate TLS with mutual authentication between workloads. Verified 2026-08-21. https://kubernetes.io/docs/concepts/security/security-checklist/
- nginx Project, Module ngx_http_ssl_module. Primary source for ssl_verify_client, ssl_client_certificate and the $ssl_client_s_dn variable Step 4 configures and reads, including the difference between on, optional and optional_no_ca that Step 4's third measurement is designed to detect. Verified 2026-08-21. https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- kind Authors, Configuration. Primary source for the kubeadmConfigPatches and nodes[].extraMounts fields the setup uses to bring the cluster up with an EncryptionConfiguration already mounted and already referenced by the kube-apiserver, and exercised with kind v0.33.0 on 2026-10-11. Verified 2026-08-21. https://kind.sigs.k8s.io/docs/user/configuration/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
