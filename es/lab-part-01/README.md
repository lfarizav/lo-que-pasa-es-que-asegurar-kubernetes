# Parte I - Laboratorio: el reglamento de visitas de la torre tres, la requisa del celador antes del turno, la portería que sí pide cédula, y el guardia nuevo al que le revisan el carné antes de dejarlo entrar

- Tiempo: 45-60 min
- Puntos: 40

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solo el objetivo, y la secuencia exacta de comandos vive en el campo cmd de ese paso, para que usted la revele después de haber intentado primero por su cuenta. El Paso 1 le pone la postura de negación por defecto del Capítulo 1, que en seguridad cubre las dos direcciones: se niega lo que entra y lo que sale, y después se abre una sola puerta con nombre propio, incluida la salida al DNS del clúster, sin la cual el vecino autorizado ni siquiera puede resolver el nombre del citófono. El Paso 2 le hace correr kube-bench de Aqua Security contra el plano de control de su propio clúster kind, leer el informe del benchmark de CIS, escoger uno de los controles fallidos que se pueden arreglar en kind, arreglarlo tocando el manifiesto del pod estático, y quedar con el clúster todavía Ready: la comprobación vuelve a correr kube-bench desde una imagen fijada por digest, así que no hay forma de silenciar el control editando la configuración de la herramienta. El Paso 3 le hace montar la portería con cédula verificada del Capítulo 2: un certificado autofirmado, un Secret de tipo kubernetes.io/tls, un Ingress con bloque tls, y la prueba que va más allá del código 200, que es comparar la huella SHA-256 del certificado que el controlador está sirviendo con la del certificado que usted guardó. El Paso 4 cierra con el binario: usted lee la versión menor del clúster de la propia API, descarga kubectl de esa línea junto con su .sha256 oficial de dl.k8s.io, comprueba que cuadran, y después adultera un solo byte de una copia para ver la comprobación fallar. Ninguna comprobación lee su historial: todas vuelven a consultar el clúster, y varias de ellas generan tráfico nuevo o vuelven a preguntarle al proyecto en el momento de calificar.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, curl, openssl, base64, sha256sum, dd y ss en el `PATH`, y con al menos 4 GB de RAM libres. El laboratorio crea su propio clúster kind llamado cks-p01 y escribe su kubeconfig en un archivo privado, ~/cks-lab/p01/kubeconfig, que no es el suyo de siempre. Todos los comandos pasan --kubeconfig apuntando a ese archivo, así que su ~/.kube/config no se modifica y ningún otro clúster suyo se toca. El teardown borra únicamente el clúster cks-p01 y la carpeta ~/cks-lab/p01.
- Los puertos 8091 y 8449 del host libres. El clúster se crea con extraPortMappings que llevan el 8091 del host al puerto 80 del nodo y el 8449 al 443, que es por donde usted toca el timbre de la portería en el Paso 3. Se escogieron esos números a propósito, y no el 8080 ni el 8443 de siempre, porque esos dos pueden estar ocupados por otro servicio de su máquina. Confirme con ss -ltn antes de empezar; si alguno está ocupado, cambie el número en kind-p01.yaml y en los comandos del Paso 3.
- Acceso a internet al montar el laboratorio y al calificarlo. El setup descarga los manifiestos de Calico, del controlador de Ingress y de kube-bench, más las imágenes de contenedor de quay.io, registry.k8s.io y docker.io. La comprobación del Paso 4 vuelve a pedirle a dl.k8s.io la suma oficial del binario, porque esa es la única forma honesta de calificar una verificación de integridad: si el archivo de la suma se lo cree el calificador sin volver a preguntarle al proyecto, usted podría escribir la suma que quiera. Si esa consulta falla, la comprobación imprime el error con nombre `ERROR SIN-INTERNET-PARA-CALIFICAR` y termina con código distinto de cero, en vez de darle un aprobado que no significa nada.
- Imagen del nodo fijada por digest, leída del binario de kind v0.32.0 el 2026-08-21 y usada sin cambios en la ejecución completa del laboratorio del 2026-10-11, hecha con kind v0.33.0, kubectl cliente v1.37.0 y Docker 29.9.0: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5. Las notas de versión de kind dicen que hay que usar el digest @sha256 para garantizar una imagen construida para esa versión, no solo el tag. Confirme la suya con kind version y con docker images --digests, nunca de memoria. La versión del servidor que trae esa imagen es v1.36.1 y el Paso 4 la lee en vivo de la API, así que si usted usa otra imagen el laboratorio se adapta solo.
- CNI fijado: Calico v3.32.1, publicado el 2026-06-26 y verificado contra las releases del proyecto el 2026-08-21. Esta pieza no es decoración. El clúster se crea con disableDefaultCNI en true precisamente porque el CNI que kind trae de fábrica no aplica NetworkPolicy, y sin un CNI que la aplique el Paso 1 entero sería teatro. Hay un detalle que se paga caro: el archivo custom-resources.yaml que publica Calico trae por defecto un pool de IPs en 192.168.0.0/16, un rango que puede chocar con el de su LAN. Por eso este laboratorio no usa ese archivo: escribe su propio recurso Installation con cidr 10.244.0.0/16, el mismo podSubnet que se le declara a kind. Los CRD van primero y explícitos, porque el operador también los instala solo, pero unos segundos después de quedar disponible, y aplicar el Installation enseguida falla con no matches for kind Installation.
- El setup mide el sustrato, no lo asume. Antes de entregarle el laboratorio, el montaje levanta un namespace de prueba desechable, comprueba que un Pod le habla a otro sin ninguna política, aplica una negación total, y vuelve a probar. Si el tráfico sigue pasando, el setup imprime el error con nombre `ERROR SUSTRATO-SIN-NETWORKPOLICY` y termina con código distinto de cero, porque en ese clúster el Paso 1 no probaría nada. Es la única forma honesta de montar un laboratorio de NetworkPolicy: un objeto puede ser aceptado por la API y no ser aplicado por nadie. Medido en la máquina de referencia el 2026-08-21: línea base con salida 0, con negación total salida 1.
- Kube-bench fijado por digest: docker.io/aquasec/kube-bench:v0.16.0@sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679, publicado el 2026-08-05, digest del índice multiplataforma leído con docker buildx imagetools inspect el 2026-08-21. Corriendo contra este clúster, kube-bench detecta la versión 1.36 y escoge solo el benchmark cis-1.12; usted no tiene que pasarle --benchmark. En el clúster recién montado el informe da 10 controles en FAIL, y ese número es determinista para esta imagen del nodo y esta versión de la herramienta. El Paso 2 se lo pregunta.
- Controlador de Ingress fijado, con una salvedad que hay que decir completa: ingress-nginx controller-v1.15.1, publicado el 2026-03-19, es la última versión que existirá. El proyecto kubernetes/ingress-nginx fue retirado y su repositorio está archivado en modo solo lectura; no habrá más correcciones de errores ni parches de seguridad, nunca. Verificado el 2026-08-21 contra la API de GitHub, que reporta archived true para ese repositorio y no lista ninguna release posterior. El manifiesto sigue descargándose porque un repositorio archivado no se borra, y el laboratorio lo usa a propósito, con el pin explícito, porque el temario del CKS sigue pidiendo asegurar un Ingress con TLS y porque saber que la empresa que le hacía mantenimiento a la entrada cerró es el tipo de cosa que un ingeniero de seguridad tiene que decir en voz alta antes de que alguien lo proponga en producción.
- Imágenes de aplicación fijadas por digest, verificadas el 2026-08-21 con docker buildx imagetools inspect: nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de para el apartamento y el citófono, y busybox:1.37@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 para los Pods cliente, que es la imagen que trae wget con tiempo de espera acotado. Un tag es mutable, un digest no.
- Haber leído los Capítulos 1 y 2. Este laboratorio no vuelve a explicar por qué un clúster sin NetworkPolicy deja que cualquier torre hable con cualquier otra, qué revisa el benchmark de CIS, por qué una portería sin TLS deja pasar a cualquiera que diga el nombre correcto, ni por qué un binario sin verificar es un guardia sin identificación propia; le hace operar las cuatro cosas contra un clúster real. Una advertencia desde ya: en el nodo de kind no hay vi ni nano, solo sed. Medido el 2026-08-21. Si usted piensa entrar al nodo a editar a mano el manifiesto de un pod estático, ese dato le ahorra un buen rato de frustración.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 1: El reglamento de visitas de la torre tres, que niega la entrada y la salida (10 pts)

El Capítulo 1 dejó el conjunto retratado: sin reglamento de visitas, cualquier persona que entre por la portería puede subir a cualquier torre, tocar cualquier puerta y quedarse conversando. En Kubernetes eso no es una metáfora suelta, es el modelo de red escrito en la documentación oficial: todos los Pods se hablan con todos los Pods sin traducción de direcciones de por medio, y ese es el estado de fábrica de su clúster.

El montaje ya le dejó tres vecinos viviendo en la torre tres. El apartamento 301 sirve una página por el puerto 80 y tiene su propio citófono, que es un Service ClusterIP llamado citofono-301. El vecino autorizado trae la etiqueta visita=autorizada. El desconocido del portal trae visita=negada. Ninguno de los tres los tiene que crear usted: lo que usted escribe es el reglamento.

Y aquí está la diferencia entre este laboratorio y uno de desarrollo. En seguridad la negación por defecto no se queda en la entrada. Una política que niega solo lo que entra deja la puerta de atrás abierta de par en par: un Pod comprometido no necesita que le entren, necesita poder salir, y con Egress sin cerrar sale a donde quiera, dentro y fuera del clúster. Su negación por defecto lleva las dos: Ingress y Egress, con podSelector vacío, sin ninguna regla adentro. Acuérdese de lo que dijo el capítulo: un podSelector vacío no selecciona a nadie, selecciona a todos los Pods del namespace.

Después abra una sola puerta, con nombre propio, y aquí viene el detalle que hace fallar en el examen: no basta con dejar entrar al vecino al apartamento. Si usted cerró la salida de todos y solo abre el egreso hacia el apartamento por el puerto 80, el vecino puede llegar por IP y no puede llegar por nombre, porque para resolver el nombre necesita hablarle al DNS del clúster, y el DNS vive en otro namespace y escucha en el puerto 53. Es un error de producción fácil de cometer con NetworkPolicy: cerrar el egreso y olvidarse del 53.

Y hágalo en el orden correcto: primero mida. Antes de aplicar nada, haga los dos wget y vea con sus propios ojos que los dos salen con código 0. Esa línea base no es un trámite, es la única manera de saber después que lo que cambió fue el reglamento y no otra cosa. El setup ya midió que este clúster aplica NetworkPolicy, pero la línea base de su namespace la mide usted.

Última advertencia: si a usted se le ocurre ponerle el carné de visita autorizada al desconocido para que el síntoma desaparezca, el tráfico va a pasar y el paso va a fallar. La pista de la comprobación lo dice de frente.

ENTREGABLE: las políticas de red que usted escriba en la-torre-tres, con los tres Pods intactos y con sus etiquetas originales, y el archivo `~/cks-lab/p01/01-respuesta.txt`, exactamente 3 líneas:

```text
SALIDA_VECINO=<el código de salida del wget del vecino autorizado contra el nombre completo del Service, después de aplicar el reglamento>
SALIDA_DESCONOCIDO=<el código de salida del wget del desconocido contra la IP del apartamento, después de aplicar el reglamento>
POLITICAS_EN_LA_TORRE=<cuántos objetos NetworkPolicy quedaron vivos en el namespace la-torre-tres>
```

<details>
<summary>Qué debería ver</summary>

En la línea base los dos wget devuelven código de salida 0: la torre está abierta y cualquier Pod le habla a cualquier otro, tal como dice el modelo de red de Kubernetes. kubectl get networkpolicies lista las tres políticas, y la de negación por defecto aparece con `POD-SELECTOR` en `<none>`, que es como kubectl muestra el selector vacío que selecciona a todos. Después de aplicar las tres, el wget del vecino autorizado por el nombre completo del Service sigue devolviendo 0, y el del desconocido se queda callado los ocho segundos completos y devuelve 1, que es como se ve un tiempo agotado y no un rechazo: nadie le contesta que no, sencillamente no le contesta. Si el vecino por nombre le devuelve 1 pero por IP le devuelve 0, no se asuste: eso significa que la salida a TCP 80 quedó abierta y la salida al DNS no, y es un error fácil de cometer en esta parte.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 1: La requisa del celador antes del turno, y arreglar una de las cosas que salieron mal (10 pts)

El Capítulo 1 terminó con la revisión antes del turno: el celador que entra no se pone a improvisar, saca la lista y va marcando. En Kubernetes esa lista se llama el benchmark de CIS, y la herramienta que la recorre sola se llama kube-bench, de Aqua Security. El setup ya le dejó escrito el manifiesto del Job, con la imagen fijada por digest, en `~/cks-lab/p01/kube-bench-job.yaml`.

Corra la requisa y lea el informe entero, no solo el resumen. Fíjese en dos cosas que es fácil pasar por alto. La primera: arriba de todo, kube-bench dice qué versión detectó y qué benchmark escogió por su cuenta, y en este clúster escoge cis-1.12 solo, sin que usted le pase --benchmark. La segunda: hay más líneas WARN que FAIL, y un WARN en CIS no es un error, es un control manual que la herramienta no puede decidir por usted.

Ahora escoja uno, no los diez. Uno solo, de los cuatro que en kind se arreglan con una sola bandera y que están listados con su número en la pista de la comprobación. Y hay un dato de la máquina, medido, que le va a ahorrar frustración: en el nodo de kind no hay vi ni nano. Solo hay sed. El manifiesto del pod estático vive adentro del contenedor del nodo, en /etc/kubernetes/manifests, así que se entra con docker exec y se edita con sed, o se saca con docker cp, se edita afuera, y se vuelve a meter.

Lo bonito de los pods estáticos es lo que pasa después: usted no reinicia nada. El kubelet está mirando esa carpeta, ve el archivo distinto, y vuelve a crear el pod solo. Espere a que el proceso vivo traiga la bandera nueva antes de recalificar, porque durante unos segundos el pod viejo todavía está ahí.

Arreglar un control de CIS no es "hacer que kube-bench deje de quejarse". Es lo que se hace cuando la auditoría aprieta: se mueve la configuración de la herramienta, o se apaga el componente, y el informe queda verde con el conjunto igual de abierto. Por eso este paso califica dos cosas al tiempo, la bandera en el proceso vivo y el clúster todavía Ready. Un plano de control apagado no falla ningún control, y no por eso está seguro.

ENTREGABLE: el control que usted escogió, arreglado en el manifiesto y visible en el comando del pod vivo, el clúster Ready, y el archivo `~/cks-lab/p01/02-respuesta.txt`, exactamente 3 líneas:

```text
CONTROL_ARREGLADO=<el número del control que usted arregló, por ejemplo 1.4.1>
FALLAS_ANTES=<cuántos checks FAIL trajo el resumen total de la primera requisa>
FALLAS_DESPUES=<cuántos checks FAIL trae el resumen total de la segunda requisa>
```

<details>
<summary>Qué debería ver</summary>

El Job termina con condition=complete y sus registros traen el informe entero. kube-bench dice arriba de todo que detectó la versión 1.36 y escogió el benchmark cis-1.12 sin que usted le pasara --benchmark. El grep de FAIL saca diez líneas en el clúster recién montado: 1.1.12 sobre la propiedad del directorio de datos de etcd, 1.2.5 sobre --kubelet-certificate-authority, 1.2.15 sobre --profiling del servidor de la API, 1.2.16 a 1.2.19 sobre las cuatro banderas de la bitácora de auditoría, 1.2.30 sobre --service-account-extend-token-expiration, 1.3.2 sobre --profiling del controller-manager y 1.4.1 sobre --profiling del scheduler. El resumen total dice 47 checks PASS, 10 checks FAIL, 50 checks WARN. Después de agregarle la bandera al scheduler, el pod estático se vuelve a crear solo en menos de un minuto, kubectl get nodes sigue diciendo Ready, y la segunda requisa saca la línea con PASS para 1.4.1 y un resumen de 9 checks FAIL.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 2: La portería con cédula verificada, y la huella que demuestra de quién es la cédula (10 pts)

El Capítulo 2 lo dijo con la portería: la que no pide nada deja entrar a cualquiera que diga el nombre correcto, porque el nombre lo dice cualquiera. La cédula es lo que no se puede decir de palabra, hay que mostrarla, y quien la mira tiene que poder comprobar que es de quien dice ser.

El montaje ya le instaló el citófono en el namespace la-porteria: un Deployment que sirve una página por el puerto 80 y su Service. Ese citófono contesta por HTTP simple y no tiene ni idea de TLS, y así se queda. Lo que usted monta es la entrada, y la entrada es la que muestra la cédula.

Son tres piezas y ninguna sobra. La primera es el certificado, que usted se genera autofirmado con openssl. Póngale el nombre de la portería en el CN, sí, pero sobre todo póngaselo en el SAN, el Subject Alternative Name: los clientes de hoy hace rato dejaron de mirar el CN, y un certificado sin SAN es una cédula sin foto. La segunda es el Secret, y tiene que ser del tipo kubernetes.io/tls, con las dos claves tls.crt y tls.key adentro; un Secret Opaque con los mismos archivos no le sirve al controlador. La tercera es el bloque tls del Ingress, que amarra un nombre de host con el nombre de un Secret, y es lo que hace que la columna `PORTS` del kubectl get ingress pase de decir 80 a decir 80, 443.

Y ahora la parte que separa a un ingeniero de seguridad de alguien que vio un tutorial. Cuando el curl le devuelva 200 y le imprima el contenido, usted todavía no ha demostrado nada. Un 200 por HTTPS no prueba que la cédula sea la suya. Prueba que hubo una cédula. ingress-nginx, cuando no encuentra el Secret que usted le nombró, no se cae ni devuelve error: saca un certificado de relleno que él mismo se firmó, con el nombre Kubernetes Ingress Controller Fake Certificate, y sigue atendiendo como si nada. La puerta se ve cerrada y la cédula es de mentiras.

Por eso el último comando de este paso abre una conexión TLS real, manda el nombre por SNI, y le saca la huella SHA-256 al certificado que le entregaron, para compararla con la del suyo. Eso es lo que hay que hacer en producción cada vez que alguien diga que ya puso el TLS.

ENTREGABLE: el Secret de tipo kubernetes.io/tls, el Ingress con su bloque tls apuntando al citófono, y el archivo `~/cks-lab/p01/03-respuesta.txt`, exactamente 3 líneas. Las dos huellas se escriben tal como las imprime openssl después del signo igual, en mayúsculas y con los dos puntos entre pareja y pareja:

```text
HUELLA_DE_MI_CERTIFICADO=<la huella SHA-256 del certificado que usted generó>
HUELLA_SERVIDA_POR_LA_ENTRADA=<la huella SHA-256 del certificado que la entrada le entregó en la conexión TLS>
CODIGO_HTTPS=<el código HTTP que devolvió el curl por https>
```

<details>
<summary>Qué debería ver</summary>

openssl imprime el certificado con subject CN igual a laporteria.local, el bloque X509v3 Subject Alternative Name con DNS:laporteria.local, y una línea sha256 Fingerprint con treinta y dos parejas de dígitos separadas por dos puntos. El Secret queda con type en kubernetes.io/tls, que es la única forma en que el controlador lo va a mirar. El Ingress se lista con `CLASS` en nginx, `HOSTS` en laporteria.local y `PORTS` en 80, 443: la columna de puertos solo incluye el 443 cuando hay bloque tls, y esa es la señal a simple vista de que la entrada quedó con cédula. El curl devuelve 200 e imprime `LA PORTERIA CON CEDULA VERIFICADA`. Y las dos últimas huellas salen idénticas, dígito por dígito. Si la segunda huella le sale distinta y el subject dice Kubernetes Ingress Controller Fake Certificate, el controlador no encontró su Secret y le está entregando a cualquier cliente su certificado de relleno: la puerta se ve cerrada y la cédula es de mentiras.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 2: Al guardia nuevo le revisan el carné antes de dejarlo entrar (10 pts)

El Capítulo 2 cerró con el guardia nuevo. Llega uno a la portería, dice que viene de la empresa de seguridad, y trae puesto el uniforme. ¿Usted lo deja entrar? La respuesta del capítulo era que el uniforme no es la identificación, y que el que revisa tiene que poder comprobar contra la empresa, no contra el señor que está parado ahí.

En una plataforma eso mismo pasa con los binarios. Usted se baja kubectl, o kubeadm, o el binario de un componente, y lo pone a correr con permisos altos contra el clúster de producción. Si el archivo venía cambiado, ya no importa cuánta RBAC haya escrito: el que está adentro es el atacante y usted mismo lo dejó pasar.

Este paso son cuatro movimientos y ninguno se salta.

El primero: la versión no se escribe de memoria. Pregúntele al clúster de qué línea es, con `kubectl get --raw /version`, y saque de ahí el major y el minor. Después pregúntele al proyecto cuál es la última estable de esa línea, que es el archivo stable de dl.k8s.io. Fíjese en un detalle: la última estable de la línea puede estar varios parches por delante de su servidor (el 2026-10-11, v1.36.5 contra v1.36.1), y eso está bien, porque el proyecto soporta un salto de una versión menor entre kubectl y el servidor.

El segundo: se baja el binario y su suma, del mismo sitio del proyecto, no del primer enlace que salga en una búsqueda.

El tercero: se comprueba antes de darle permiso de ejecución. Ese orden no es capricho. Un binario sin chmod +x es un archivo cualquiera; con chmod +x es un programa que usted acaba de autorizar. Compruebe primero, autorice después.

El cuarto es el que enseña, y por eso este laboratorio lo obliga: haga una copia y cámbiele un solo byte, sin tocarle el tamaño. Después vuelva a comprobar y mire el FAILED. No vale con borrar el archivo o dejarlo vacío para que la comprobación falle: eso ya se ve a simple vista y no demuestra nada. Lo que hay que ver con los ojos propios es que un archivo que pesa lo mismo, que se ve igual y que tiene la misma fecha, se cae entero con una sola letra cambiada en el medio. Esa es toda la razón de existir de un hash.

ENTREGABLE: la carpeta `~/cks-lab/p01/binario` con el binario kubectl descargado y ejecutable, su archivo kubectl.sha256 tal como lo publicó el proyecto, y la copia kubectl-adulterado del mismo tamaño con un byte cambiado; más el archivo `~/cks-lab/p01/04-respuesta.txt`, exactamente 4 líneas:

VERSION_DESCARGADA=<la versión que usted descargó, con la v adelante>
SHA256_OFICIAL=<los 64 caracteres de la suma que publicó el proyecto>
RESULTADO_ORIGINAL=OK
RESULTADO_ADULTERADO=FALLA

<details>
<summary>Qué debería ver</summary>

`kubectl get --raw /version` imprime el JSON del servidor con major en 1 y minor en 36, y de ahí sale la línea. El archivo stable-1.36.txt del proyecto devuelve la última estable de esa línea, que el 2026-10-11 era v1.36.5; fíjese en que no es la misma versión del servidor, v1.36.1, y que eso está bien, porque kubectl soporta un salto de una versión menor arriba o abajo. El .sha256 pesa 64 bytes, o sea los 64 caracteres hexadecimales de la suma sin salto de línea, y el binario pasa de 50 MB (59584674 bytes el 2026-10-11). La primera comprobación imprime kubectl: OK y sale con código 0. La segunda imprime kubectl-adulterado: FAILED, más la línea WARNING: 1 computed checksum did NOT match, y sale con código 1. Y fíjese en el ls: los dos archivos pesan lo mismo. Un solo byte cambiado en 50 MB, ningún cambio de tamaño, y la suma se cae entera. El ./kubectl version --client responde con la misma versión que usted descargó (`Client Version: v1.36.5` el 2026-10-11).

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

- **Síntoma (step 1):** El vecino autorizado llega por IP pero no llega por nombre
  **Qué hacer:** Le faltó abrir el egreso hacia el DNS del clúster. Agregue a la política de egreso una segunda entrada en la lista to que apunte al namespace kube-system, por su etiqueta kubernetes.io/metadata.name, y adentro al podSelector k8s-app=kube-dns, con los puertos 53 UDP y 53 TCP. Confirme la etiqueta del namespace con $K get ns kube-system --show-labels y la del Pod con $K -n kube-system get pods -l k8s-app=kube-dns --show-labels, en vez de escribirlas de memoria.

- **Síntoma (step 1):** Después de aplicar el reglamento, el desconocido sigue entrando con código 0
  **Qué hacer:** Ese es el síntoma del celador de mentiras, y lo primero que hay que descartar es el CNI. Confirme que Calico quedó vivo con $K get tigerastatus y que los Pods de calico-system están Running; si el clúster se creó sin disableDefaultCNI, las políticas quedan guardadas en la API y no las aplica nadie. Lo segundo es que las políticas estén en el namespace la-torre-tres y no en default: un NetworkPolicy solo actúa dentro de su propio namespace. Y lo tercero, deje pasar unos segundos: el CNI no programa las reglas en el mismo instante del apply.

- **Síntoma (step 1):** El wget del desconocido se queda colgado y nunca vuelve
  **Qué hacer:** Le faltó el tiempo de espera. Un paquete bloqueado por NetworkPolicy no rebota, se pierde, así que sin -T el wget espera el tiempo por defecto del sistema y usted se queda mirando la terminal. Use -T 5 como en el comando de este paso; ese número acotado es lo que convierte el bloqueo en un código de salida que se puede medir.

- **Síntoma (step 2):** El Job de kube-bench se queda en Pending y nunca arranca
  **Qué hacer:** El único nodo de este clúster es de plano de control y trae la marca node-role.kubernetes.io/control-plane con efecto NoSchedule, así que un Pod sin tolerancia no se puede programar ahí. El manifiesto que dejó el setup ya trae el nodeSelector y la tolerancia; si usted escribió el suyo copiando el job.yaml del proyecto, agréguelas. Confirme la causa exacta con $K describe pod -l app=kube-bench y lea los eventos.

- **Síntoma (step 2):** Edite el manifiesto y el pod estático no cambia
  **Qué hacer:** Revise tres cosas. Que haya editado el archivo adentro del contenedor del nodo, en /etc/kubernetes/manifests, y no una copia en su máquina. Que la sangría de la línea nueva sea igual a la de las otras banderas, cuatro espacios y un guion: un YAML mal sangrado hace que el kubelet rechace el archivo en silencio. Y que le haya dado tiempo: el kubelet revisa la carpeta cada pocos segundos. Mire el comando que quedó corriendo con $K -n kube-system get pod kube-scheduler-$NODO -o jsonpath='{.spec.containers[0].command}'.

- **Síntoma (step 2):** Toque el servidor de la API y ahora kubectl no responde
  **Qué hacer:** Es lo esperado durante unos treinta a sesenta segundos: el pod estático del servidor de la API se está volviendo a crear y no hay a quien preguntarle. Espere y reintente. Si pasado un par de minutos sigue sin responder, la bandera quedó mal escrita: mire el contenedor con docker exec $NODO crictl ps -a y sus registros con docker exec $NODO crictl logs <id>, corrija el manifiesto con sed y espere otra vez. Nada de esto necesita reiniciar el nodo.

- **Síntoma (step 3):** curl dice que no puede conectar con el puerto 8449
  **Qué hacer:** Ese puerto solo existe porque el clúster se creó con extraPortMappings. Confirme con docker port cks-p01-control-plane que el 8449 del host está mapeado al 443 del nodo; si no aparece, el clúster se creó sin el archivo kind-p01.yaml y hay que rehacerlo, porque extraPortMappings no se puede agregar a un clúster ya creado.

- **Síntoma (step 3):** La huella servida no coincide y el subject dice Fake Certificate
  **Qué hacer:** El controlador no encontró su Secret. Revise en este orden: que el Secret esté en el mismo namespace que el Ingress, porque secretName no cruza namespaces; que el nombre escrito en spec.tls[0].secretName sea idéntico al del Secret; que el tipo del Secret sea kubernetes.io/tls y no Opaque; y que el host de la regla aparezca también dentro de spec.tls[0].hosts, porque el controlador escoge el certificado por el nombre que le llega en el SNI. Y deje pasar unos segundos: la recarga no es instantánea.

- **Síntoma (step 3):** kubectl apply del Ingress falla con un error del webhook de admisión
  **Qué hacer:** ingress-nginx instala un ValidatingWebhookConfiguration que revisa cada Ingress antes de aceptarlo. Si el controlador todavía no terminó de arrancar, ese webhook no responde y el apply falla. Espere a que el Pod del controlador esté listo con $K wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s y vuelva a aplicar.

- **Síntoma (step 4):** sha256sum --check dice: no properly formatted checksum lines found
  **Qué hacer:** El archivo .sha256 que publica el proyecto trae únicamente la suma, sin el nombre del archivo al lado, y sha256sum --check espera el formato suma, dos espacios, nombre. Arme la línea usted mismo antes de comprobar, como hace el comando de este paso. Ojo con los dos espacios: con uno solo tampoco lo reconoce.

- **Síntoma (step 4):** El binario descargado pesa unos pocos kilobytes
  **Qué hacer:** Le faltó seguir la redirección. dl.k8s.io responde con un redirect hacia el almacenamiento real, así que curl necesita -L; sin esa bandera usted se baja la página del redirect y no el programa. Use -sSLO como en el comando de este paso, borre lo que bajó mal y vuelva a intentar.

- **Síntoma (step 4):** La comprobación falla y yo veo que la suma del archivo sí cuadra con el binario
  **Qué hacer:** Que el archivo local cuadre consigo mismo no demuestra nada, y esa es justo la lección. La comprobación vuelve a pedirle la suma a dl.k8s.io y compara contra esa. Revise que la versión que declaró sea la que hoy dice stable-<major>.<minor>.txt, porque esa línea recibe parches y puede haber cambiado desde que usted descargó; en ese caso vuelva a descargar el binario y la suma, y actualice las dos lineas del archivo de respuestas.

## Para ir más lejos

- Agréguele a la torre tres una cuarta política que le abra el egreso al vecino autorizado hacia fuera del clúster, por ejemplo hacia 1.1.1.1 por el puerto 443, usando un bloque ipBlock en vez de un podSelector. Después quítele el except y vuelva a ponérselo, y observe qué pasa cuando el rango exceptuado se solapa con el rango del pool de IPs de Calico. Es la forma más rápida de entender por qué una política de egreso escrita con CIDR envejece mal cuando la red del clúster cambia.
- Escoja un segundo control de la lista de arreglables del Paso 2, arréglelo también, y vuelva a correr kube-bench. Anote cuánto bajó el número de FAIL y cuánto no bajó el número de WARN. Después lea la sección de remediación que kube-bench imprime al final para uno de los controles que quedaron en WARN y explique con sus propias palabras por qué esa comprobación no la puede automatizar la herramienta.
- Cree un segundo Secret de TLS con un certificado para otro nombre, agréguele al mismo Ingress una segunda regla de host y un segundo bloque tls, y compruebe con openssl s_client que cambiando solo el -servername el mismo controlador le entrega dos certificados distintos por el mismo puerto. Eso es SNI funcionando, y es la razón por la que el bloque tls lleva una lista de hosts y no un host suelto.
- Repita el Paso 4 con el binario de kubeadm de la misma versión, que se publica en la misma ruta de dl.k8s.io con su propio .sha256, y compare las dos sumas. Después busque en la documentación oficial de Kubernetes la página de firmas de artefactos y averigüe qué le añade una firma de sigstore que un sha256 solo no le da. La respuesta es la diferencia entre integridad y procedencia, y es la que el Capítulo 12 va a necesitar.

## Referencias

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
