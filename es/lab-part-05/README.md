# Parte V - Laboratorio: la bodega que se adelgaza, la caja que se pide por factura y no por apodo, el proveedor que trae la plaga adentro, y el sello que la portería sí revisa

- Tiempo: 55 min
- Puntos: 40

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia exacta de comandos vive en el campo cmd de ese paso para que usted la revele después de haber intentado por su cuenta. Los cuatro pasos recorren el dominio Supply Chain Security del CKS de arriba abajo, y los cuatro se califican midiendo el mundo real, no leyendo lo que usted escribió. El Paso 1 le entrega un Dockerfile inflado que deja el compilador entero adentro de la imagen de producción, y le exige convertirlo en una construcción multietapa cuya imagen final quede por debajo de un tamaño declarado y además siga sirviendo la carta por HTTP: las dos cosas se miden, la primera con docker image inspect y la segunda levantando el contenedor y pidiéndole la página (Capítulo 10). El Paso 2 le entrega un Deployment que pide su imagen por etiqueta, o sea por apodo, y le exige repintarlo por digest; la comprobación va al registro vivo, le pregunta cuál es el digest de esa etiqueta hoy, y compara contra el spec del Deployment y contra el imageID que el kubelet reporta en cada Pod, así que una etiqueta suelta en cualquier parte del namespace lo reprueba (Capítulo 11). El Paso 3 le pone dos imágenes candidatas de dos proveedores distintos y le exige encontrar con trivy cuál de las dos trae una vulnerabilidad CRITICAL adentro, desplegar solamente la limpia, y anotar el identificador CVE; la comprobación vuelve a escanear las dos con el mismo trivy fijado y exige que el CVE que usted nombró esté presente en la rechazada y ausente de la aprobada (Capítulos 10 y 11). El Paso 4 cierra con cosign contra un registro local: usted genera su llave, firma la imagen aprobada, y escribe una política de admisión que exige ese sello en la puerta; la comprobación verifica la firma con cosign por fuera del clúster, comprueba que la imagen sin firma no verifica, y después crea Pods en vivo para ver que la firmada entra con su digest pegado y la sin firma se queda afuera (Capítulo 12). Borrar la política para que deje de molestar hace fallar el paso, y firmar también la imagen sucia para que todo pase lo hace fallar igual.

## Prerrequisitos

- Una máquina Linux con docker, kind, kubectl, helm, jq y curl en el `PATH`, con salida a internet durante la preparación, y con al menos 4 GB de RAM libres. El laboratorio crea su propio clúster kind llamado cks-p05, su propio registro local en el contenedor cks-p05-registry publicado en 127.0.0.1:5065, y borra las dos cosas en el teardown.
- Aislamiento: esto no es un detalle de estilo. El clúster de este laboratorio no toca su kubeconfig habitual: se crea con --kubeconfig ~/cks-lab/p05/kubeconfig desde el primer comando, y todos los kubectl y helm del laboratorio pasan --kubeconfig y --context de forma explícita. Si usted ya tiene otros clústeres de kind corriendo en esta máquina, este laboratorio no los ve, no los modifica y no los borra. Compruébelo usted mismo: al final del setup se imprime un kubectl config get-contexts sin --kubeconfig, y ahí no debe aparecer ni rastro de cks-p05. El registro también es propio: nombre único y puerto único, para que no se le monte encima a ningún otro registro local que usted tenga andando.
- Paciencia con la preparación: el setup baja la imagen del nodo de kind, la imagen del registro, la imagen de golang que pesa cerca de 1,3 GB en disco, dos archivos .jar del repositorio central de Maven, el binario de cosign, el binario de trivy y la base de datos de vulnerabilidades de trivy, y además instala Kyverno con helm. En una máquina que empiece de cero eso son entre 10 y 20 minutos. Ese tiempo es sustrato, no cuenta en su nota; los 55 minutos del laboratorio son los cuatro pasos calificados.
- Versiones y digests fijados; el laboratorio se ejecutó completo el 2026-10-11 en esta misma máquina con kind v0.33.0, kubectl cliente v1.37.0, Docker 29.9.0 con el snapshotter de containerd y helm v4.3.0. Además: jq 1.7. cosign v2.6.5, que es la serie que todavía firma sin transparencia con --tlog-upload=false. trivy v0.74.0. Chart de Kyverno 3.9.0, aplicación v1.19.0. Imagen del nodo kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5. Registro registry:3@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33. Base gorda golang:1.25@sha256:fe5d57d3b718e7a4986bae156c2d73f44973bfd313073aed08a4de6692bb6161. Base flaca sugerida alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce. Un tag es mutable y un digest no: por eso todo va fijado y por eso el Paso 2 existe. Confirme lo que le quedó instalado con kind version, kubectl version y docker version, nunca de memoria.
- Haber leído los Capítulos 10, 11 y 12. Este laboratorio no vuelve a explicar por qué una imagen base pequeña tiene menos de donde robar, ni qué es un digest, ni cómo cosign guarda una firma en el registro; le hace operar las tres cosas contra un clúster real y un registro real, y le califica el estado final.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 10: La bodega no se sube a la vitrina, y el compilador no se despacha con el pan (10 pts)

El Capítulo 10 le explicó la idea con la tienda de la esquina: entre más mercancía haya guardada en la trastienda, más hay de dónde robar, y lo que hay guardado no hace falta para vender pan. Lo que pasa es que en el mundo de los contenedores esa trastienda se construye sin darse cuenta, porque el Dockerfile más natural es el que compila y despacha en el mismo lugar.

Abra el `Dockerfile.bodega` que le dejó la preparación. Es una sola etapa. Arranca de la imagen oficial de Go, que trae el compilador, el linker, git, la biblioteca estándar completa y un sistema operativo entero por debajo. Compila su programa. Y despacha esa misma imagen a producción. El binario que usted necesita pesa unos pocos megabytes; lo que va a viajar al clúster pesa cientos.

Eso no es "un poco de peso de más", es superficie de ataque. Cada compilador que queda adentro es una herramienta que un atacante ya no tiene que subir. Cada `curl`, cada `wget`, cada shell, cada gestor de paquetes es un escalón que usted le dejó puesto. Y cada paquete del sistema base es un CVE potencial que le va a salir en el escaneo del Paso 3 sin que su código tenga nada que ver.

La construcción multietapa existe para esto: una etapa que compila con todas las herramientas del mundo, y una etapa final que empieza de cero y a la que usted le copia únicamente el resultado. Lo que no se copia, no existe. Y cuando la etapa final es `scratch`, lo que queda adentro es un solo archivo: su binario. Ni shell, ni gestor de paquetes, ni nada que abrir.

Un detalle práctico para que no se le caiga: `scratch` no trae bibliotecas del sistema, así que el binario tiene que ser estático. El `Dockerfile.bodega` ya le dejó `CGO_ENABLED=0` puesto, que es lo que hace que Go compile sin enlazar contra la libc del sistema. Si usted decide usar `alpine` en vez de `scratch` también le va a funcionar y va a quedar por debajo del límite, con la ventaja de tener un shell para depurar y la desventaja de tener un shell para que otro depure.

ENTREGABLE: la imagen `la-tienda:flaca`, construida a partir de `~/cks-lab/p05/la-tienda/tienda.go`, con el ejecutable en `/tienda`, un tamaño reportado por `docker image inspect` menor que 26.214.400 bytes (25 MiB), sin el compilador de Go adentro, y sirviendo por el puerto 8080 la carta en la raíz y la versión de Go en `/version`. La imagen `la-tienda:bodega` no se puede borrar: el paso compara las dos. Además el archivo `~/cks-lab/p05/01-respuesta.txt`, exactamente 4 líneas:

```text
TAMANO_BODEGA=<bytes que reporta docker image inspect de la imagen inflada>
TAMANO_FLACA=<bytes que reporta docker image inspect de su imagen final>
CARTA_QUE_SIRVE=<la línea que el contenedor devuelve en la raíz del puerto 8080>
VERSION_DE_GO=<la línea que el contenedor devuelve en `/version`>
```

<details>
<summary>Qué debería ver</summary>

El Dockerfile.bodega que le dejó el setup tiene una sola etapa: arranca de golang:1.25 fijado por digest, compila el binario adentro, y despacha esa misma imagen a producción con el compilador, el linker, git y toda la biblioteca estándar de Go todavía puestos. El docker image inspect de esa imagen devolvió 1.366.669.432 bytes el 2026-10-11 (unos 1,37 GB), y el docker image ls puede mostrar otra cifra en su columna `DISK USAGE`, porque son dos formas distintas de medir la misma imagen; el laboratorio califica con el número de inspect, que es el que no depende de qué más tenga usted en el disco. Después de la conversión a multietapa con etapa final scratch, el mismo inspect devolvió 7.989.501 bytes: la imagen quedó unas 171 veces más pequeña y sigue siendo el mismo programa. El contenedor levanta sin shell, sin gestor de paquetes y sin nada más que un ejecutable, y aun así el curl le devuelve pan-de-la-esquina-v1 en la raíz y go1.25.12 (el valor observado el 2026-10-11) en `/version`. Ese segundo endpoint es el que le prueba que lo que está corriendo es un binario de Go compilado y no un archivo de texto servido por ahí.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 11: La caja se pide por factura, no por apodo, porque el apodo se lo cambian sin avisarle (10 pts)

El Capítulo 11 le contó lo de la factura: la tienda necesita saber de dónde vino cada caja, y saberlo de una forma que el proveedor no pueda cambiar después. Un tag de imagen no es una factura, es un apodo. `pan:v1` no significa "esta caja"; significa "la caja que hoy se llama v1". Y quien tenga permiso de escritura en ese repositorio puede volver a subir otra cosa con ese mismo apodo esta noche, sin avisarle a nadie, y mañana su Deployment arranca un Pod nuevo con contenido distinto y el mismo YAML.

Que el Pod ya esté corriendo no lo deja a salvo: le sirve hasta que se reinicie. El día que ese nodo se caiga, o que usted escale, o que el kubelet reprograme, el contenedor nuevo sale del apodo, no del que usted revisó.

Un digest sí es una factura. Es el hash del manifiesto: si le cambian un byte al contenido, el digest cambia, y una referencia `repositorio@sha256:...` que ya no coincide simplemente no se puede resolver. No hay forma de reemplazar el contenido dejando el mismo digest.

Y aquí hay un detalle que desconcierta. Mire el `imageID` de los Pods que ya están corriendo, antes de que usted toque nada. Ya dice un digest. El kubelet siempre resuelve el apodo a un digest y corre ese digest. O sea que el digest siempre estuvo ahí; lo único que cambia cuando usted lo escribe en el spec es quién decide cuál es: si usted, o el que tenga la llave del repositorio.

Este paso le pide convertir la vitrina. La respuesta a "cuál es el digest" no se la inventa: se la pregunta al registro, que es la fuente.

ENTREGABLE: el Deployment `la-vitrina` del namespace `la-vitrina` pidiendo su imagen por digest, con 2 réplicas listas, y ningún Pod del namespace pidiendo imagen por tag. El digest tiene que ser el que el registro reporta hoy para `tienda/pan:v1`. Además el archivo `~/cks-lab/p05/02-respuesta.txt`, exactamente 3 líneas:

```text
DIGEST_DEL_REGISTRO=<el digest que el registro reporta para el tag v1>
IMAGEN_DEL_DESPLIEGUE=<la referencia completa que quedó en el spec del Deployment>
REPLICAS_LISTAS=<cuántas réplicas reporta el Deployment como listas>
```

<details>
<summary>Qué debería ver</summary>

Antes de tocar nada, el spec del Deployment dice cks-p05-registry:5000/tienda/pan:v1, un apodo, y sin embargo el imageID de cada Pod ya dice cks-p05-registry:5000/tienda/pan@sha256:caef363d... Fíjese en esa asimetría, porque es la idea entera del capítulo: el kubelet siempre termina corriendo un digest, usted es el que decidió no escribirlo. La consulta `HEAD` al registro le devuelve una cabecera Docker-Content-Digest con ese mismo sha256, que es la respuesta a la pregunta a qué apunta el apodo hoy. Después del set image el rollout arranca Pods nuevos, y ahora el spec y el imageID dicen lo mismo. La imagen ya no tiene tag por ningún lado: dice repositorio@sha256:..., y eso ya no se lo puede cambiar nadie por debajo, porque si le cambian el contenido cambia el digest y el digest lo lleva usted escrito.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 11: Dos proveedores traen la misma caja, y uno de los dos la trae con plaga adentro (10 pts)

El Capítulo 11 le dejó una idea incómoda: la caja puede venir sellada, con factura, del proveedor de siempre, y traer la plaga adentro. Usted no empacó lo que hay adentro de la caja. Lo empacó alguien más, hace meses, y usted lo único que hizo fue escribir una línea que dice que lo quiere.

La preparación le dejó dos imágenes candidatas en el registro del laboratorio, `tienda/proveedor-a:2026-08` y `tienda/proveedor-b:2026-08`. Por fuera son idénticas: la misma base, un tamaño muy parecido, el mismo comando. Adentro, cada una trae empacada una biblioteca de registro de eventos, y una de las dos viene de un lote viejo. Cuál es cuál no lo decide su intuición ni el nombre del proveedor: lo decide el escáner.

Mirar la imagen base no basta. Las dos imágenes salen de la misma alpine y las dos le van a reportar cero vulnerabilidades del sistema operativo. El hallazgo no está en el sistema, está en un archivo `.jar` que alguien copió adentro. Un escáner serio no se queda en los paquetes del sistema: entra a las dependencias empacadas por lenguaje, y ahí es donde sale la verdad.

Y una precisión sobre las palabras, porque en el examen importan. Una vulnerabilidad no es lo mismo que un riesgo. Que trivy le reporte CRITICAL significa que esa versión de esa biblioteca tiene un defecto conocido de gravedad crítica, no que su aplicación lo esté ejecutando. Pero en la puerta de un clúster, con las manos en el teclado y el reloj corriendo, la política es sencilla: la caja con crítica no sube a la vitrina.

Este paso le pide hacer de comprador: escanear las dos, decidir con evidencia, desplegar solamente la buena, y dejar por escrito cuál es el defecto que le hizo rechazar la otra.

ENTREGABLE: en el namespace `la-bodega`, un Deployment llamado `el-proveedor` con 2 réplicas listas corriendo solo la imagen del proveedor limpio, y ninguna copia de la imagen del proveedor rechazado corriendo en ese namespace. Use el nombre `cks-p05-registry:5000` para que el clúster resuelva el registro. Además el archivo `~/cks-lab/p05/03-respuesta.txt`, exactamente 3 líneas:

```text
CVE_CRITICO=<el identificador CVE, en mayúsculas, de una vulnerabilidad CRITICAL que trivy reporta en la imagen rechazada y no reporta en la aprobada>
PROVEEDOR_RECHAZADO=<el repositorio del proveedor que rechazó, en la forma tienda/proveedor-X>
PROVEEDOR_APROBADO=<el repositorio del proveedor que desplegó, en la forma tienda/proveedor-X>
```

<details>
<summary>Qué debería ver</summary>

El primer escaneo le devuelve una tabla de resumen con dos filas: el sistema operativo de la imagen, alpine 3.22.5, con 0 vulnerabilidades, y una segunda fila que dice opt/despacho/lib/log4j-core-2.14.1.jar de tipo jar, con 2. Lea eso despacio, porque es la lección del paso: la base estaba impecable y la plaga venía adentro de una dependencia empacada en la caja. La tabla de detalle nombra CVE-2021-44228 y CVE-2021-45046, las dos en CRITICAL, las dos contra org.apache.logging.log4j:log4j-core en versión instalada 2.14.1, y le dice cuáles versiones lo arreglan. El segundo escaneo, el del otro proveedor, le devuelve la misma estructura con 0 y 0: mismo sistema operativo, misma biblioteca, versión distinta, ninguna crítica. Después el Deployment de la caja limpia queda con 2 réplicas listas y el imageID de sus Pods apunta al digest de esa imagen.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 12: El sello de garantía no sirve de nada si el celador no lo revisa (10 pts)

El Capítulo 12 cerró la parte con la idea que amarra todo: usted ya sabe adelgazar la caja, ya sabe pedirla por factura y ya sabe revisarle la plaga. Falta la firma del proveedor autorizado, y falta alguien en la puerta que la revise. Es fácil pasar por alto la segunda mitad de esa frase.

Firmar es fácil: `cosign sign` con su llave privada, y listo. Y hay un detalle que conviene conocer: la firma no le queda en un archivo al lado de la imagen. Se sube al mismo registro, como un artefacto más, con un tag derivado del digest de la imagen firmada. O sea que la firma viaja con la caja, no en un cajón aparte, y por eso cualquiera que pueda leer el repositorio puede verificarla sin pedirle nada a usted.

Pero firmar por sí solo no protege nada. Una firma que nadie verifica es una calcomanía. El control real está en la puerta: un webhook de admisión que, antes de dejar entrar cualquier Pod, toma la referencia de la imagen, va al registro, busca la firma, la verifica contra la llave pública que usted le declaró, y si no cuadra rechaza la creación del Pod. Sin ese celador, usted puede firmar todas las imágenes del mundo y el clúster va a seguir corriendo cualquier cosa.

Hay un regalo escondido en esa regla, y es la razón por la que este paso cierra la parte entera: cuando la verificación pasa, el webhook reescribe la referencia de la imagen para dejarla fijada al digest exacto que acabó de verificar. O sea que la política de firma le impone además la disciplina del Paso 2, automáticamente, y sin que nadie tenga que acordarse. Verificar por tag sería absurdo: si el tag se puede mover, verificar el tag no verifica nada.

Una advertencia sobre la firma de este laboratorio: se hace con `--tlog-upload=false`, sin registro público de transparencia, porque su registro es local y no hay a dónde publicar. Por eso al verificar hay que decir explícitamente que ignore el log, y por eso la política necesita `rekor.ignoreTlog`. En producción con Sigstore público es al revés, y esa asimetría vale la pena que la vea con las manos.

La caja aprobada es la que usted aprobó en el Paso 3. Este paso depende de esa conclusión.

ENTREGABLE: un par de llaves cosign en `~/cks-lab/p05/despacho.key` y `~/cks-lab/p05/despacho.pub`; la imagen del proveedor aprobado firmada por digest con esa llave en el registro del laboratorio, y la imagen del proveedor rechazado sin firmar; una ClusterPolicy con una regla `verifyImages` en Enforce que exija esa llave para las imágenes `cks-p05-registry:5000/tienda/*` que lleguen al namespace `el-deposito`; y en ese namespace un Pod llamado `el-aprobado` corriendo la imagen aprobada. Además el archivo `~/cks-lab/p05/04-respuesta.txt`, exactamente 2 líneas:

```text
POLITICA_VERIFY=<el nombre de la ClusterPolicy que exige la firma>
DIGEST_FIRMADO=<el digest sha256 de la imagen que usted firmó>
```

<details>
<summary>Qué debería ver</summary>

El generate-key-pair le escribe despacho.key y despacho.pub sin pedirle contraseña porque COSIGN_PASSWORD va vacío. El sign termina con una línea que dice Pushing signature to: 127.0.0.1:5065/tienda/proveedor-b, y eso es literal: la firma no va en un archivo aparte, va al mismo registro, guardada como un artefacto más con un tag derivado del digest de la forma sha256-<digest sin prefijo>.sig. El verify de la firmada termina bien; el de la sin firma termina en error con un mensaje que dice no signatures found. Al aplicar la ClusterPolicy le va a salir un aviso de que ClusterPolicy está en desuso y de que hay que migrar a las políticas de policies.kyverno.io (por ejemplo ImageValidatingPolicy): es un aviso, no un error, y en el chart 3.9.0 que este laboratorio fija la regla funciona. Después el Pod el-aprobado se crea, y al leerlo del clúster su imagen ya no termina en :2026-08 sino en :2026-08@sha256:..., porque mutateDigest le clavó el digest exacto que Kyverno acabó de verificar. Y el Pod el-rechazado no se crea: el servidor responde con un error del webhook mutate.kyverno.svc-fail que dice failed to verify image ... no signatures found. Ese error es el paso pasando, no fallando.

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

- **Síntoma (step 1):** El contenedor de la imagen final arranca y se muere de inmediato, o dice no such file or directory aunque el archivo sí está
  **Qué hacer:** Ese mensaje engañoso aparece cuando el binario es dinámico y la etapa final no tiene la biblioteca contra la que fue enlazado. El archivo que no encuentra no es su binario, es el cargador dinámico. Compile con CGO_ENABLED=0 en la etapa constructora, que es lo que hace que Go produzca un ejecutable estático. Compruébelo sacando el binario con docker create y docker cp y mirándolo con file: tiene que decir statically linked.

- **Síntoma (step 1):** docker image ls y docker image inspect le dan números muy distintos para la misma imagen
  **Qué hacer:** No es un error, son dos medidas distintas. Con el snapshotter de containerd, docker image ls le muestra una columna `DISK USAGE`, que es lo que ocupan las capas descomprimidas en su disco, y una columna `CONTENT SIZE`, que es el contenido direccionable por contenido. El campo .Size de docker image inspect corresponde a esa segunda medida. La comprobación usa inspect a propósito, porque es la que no cambia según qué otras imágenes compartan capas con la suya.

- **Síntoma (step 1):** El curl al contenedor no responde y usted no publicó ningún puerto
  **Qué hacer:** En Linux usted puede hablarle directo a la IP del contenedor sin publicar puertos, y por eso este paso no usa -p: así no le pisa ningún puerto a otro laboratorio que usted tenga corriendo. Saque la IP con docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' y péguele a esa IP en el 8080. Si prefiere publicar, publique en 127.0.0.1 y en un puerto que nadie más esté usando, pero revise antes con ss -ltn.

- **Síntoma (step 2):** El curl al registro no devuelve la cabecera Docker-Content-Digest
  **Qué hacer:** Revise primero la cabecera Accept. La API de distribución le devuelve el manifiesto en el formato que usted diga que acepta, y si no dice ninguno le puede devolver un formato viejo o un 404. Mande la petición con -I, que hace `HEAD`, y con un Accept que incluya application/vnd.oci.image.manifest.v1+json y application/vnd.docker.distribution.manifest.v2+json. Y acuérdese de quitar el retorno de carro con tr -d '\r' antes de comparar, porque las cabeceras HTTP terminan en `CRLF` y el digest le queda con basura invisible al final.

- **Síntoma (step 2):** Los Pods nuevos se quedan en ErrImagePull después de que usted puso el digest
  **Qué hacer:** Revise que no cambió el nombre del repositorio al pegar el digest. El nombre que el clúster resuelve es cks-p05-registry:5000, que es el nombre del contenedor del registro dentro de la red de docker; 127.0.0.1:5065 es el nombre que resuelve su máquina y adentro del nodo no significa nada. El digest sí es el mismo por los dos caminos, porque es el mismo registro y el mismo repositorio; lo único que cambia es el host con el que usted lo alcanza.

- **Síntoma (step 2):** Usted quiere dejar el tag y el digest al mismo tiempo y no sabe si vale
  **Qué hacer:** Sí vale, y es una forma válida: repositorio:v1@sha256:... se lee bien para un humano y se resuelve por digest para el kubelet, porque cuando hay digest el tag es decoración. La comprobación acepta esa forma. Lo que no acepta es una referencia sin digest, porque ahí el tag deja de ser decoración y vuelve a mandar.

- **Síntoma (step 3):** trivy se demora muchísimo la primera vez o falla bajando la base de datos
  **Qué hacer:** La primera ejecución baja la base de datos de vulnerabilidades y la guarda en el directorio de caché. La preparación ya la bajó a ~/cks-lab/p05/trivy-cache, así que exporte TRIVY_CACHE_DIR apuntando ahí antes de escanear y va a reutilizarla. Si su red bloquea el registro de donde sale la base, el escaneo no se puede hacer y el Paso 3 no es calificable; dígalo en vez de inventar el resultado.

- **Síntoma (step 3):** trivy le reporta cero vulnerabilidades en las dos imágenes
  **Qué hacer:** Revise dos cosas. Primero, que no le puso --severity con un filtro que deja por fuera lo que busca; empiece sin filtro y después filtre. Segundo, que está escaneando la imagen del registro y no un nombre local que apunta a otra cosa; escanee 127.0.0.1:5065/tienda/proveedor-a:2026-08 tal cual. Si las dos salen limpias, la base de datos cambió y la preparación se lo habría dicho con `ERROR DE SUSTRATO: TRIVY-NO-SEPARA-LAS-CAJAS` antes de dejarlo empezar.

- **Síntoma (step 3):** El Deployment se crea pero los Pods se quedan en ImagePullBackOff
  **Qué hacer:** Probablemente usó 127.0.0.1:5065 en el manifiesto. Ese nombre lo resuelve su máquina, no el nodo: adentro del nodo 127.0.0.1 es el nodo mismo. El nombre que el clúster resuelve es cks-p05-registry:5000, que es el contenedor del registro conectado a la red de docker llamada kind. Escanee con el primero y despliegue con el segundo; es el mismo registro por dos puertas.

- **Síntoma (step 4):** cosign sign le pide una contraseña y usted no puso ninguna
  **Qué hacer:** La llave privada de cosign se guarda cifrada y el binario pide la clave por consola. Exporte COSIGN_PASSWORD vacío antes de generar el par y antes de firmar, y no se la vuelve a pedir. Si usted generó el par con una contraseña y ya no se acuerda, borre despacho.key y despacho.pub y vuelva a generarlos: como todavía no ha firmado nada con esa llave, no pierde nada.

- **Síntoma (step 4):** Kyverno rechaza también la imagen firmada, con un mensaje sobre el log de transparencia
  **Qué hacer:** Son tres cosas y conviene revisarlas en orden. Primero, que la llave pública quedó pegada en el YAML con su indentación intacta, incluidas las líneas `BEGIN PUBLIC KEY` y `END PUBLIC KEY`; una sola línea corrida y la llave deja de ser válida. Segundo, que la firma se hizo con --tlog-upload=false y que por eso la política necesita rekor.ignoreTlog en true y ctlog.ignoreSCT en true; sin eso Kyverno sale a buscar una entrada pública que esa firma nunca tuvo. Tercero, que Kyverno quedó instalado con features.registryClient.allowInsecure en true, porque el registro del laboratorio habla HTTP y no HTTPS; el setup ya lo instala así.

- **Síntoma (step 4):** Usted firmó con el nombre de host 127.0.0.1:5065 y le preocupa que el clúster lo vea con otro nombre
  **Qué hacer:** No hay problema, y entender por qué vale por medio capítulo. El host no es parte del repositorio: cosign guarda la firma dentro del repositorio tienda/proveedor-b del mismo registro, bajo un tag derivado del digest. Kyverno alcanza ese mismo repositorio por el nombre cks-p05-registry:5000 y encuentra la misma firma. Lo que sí importa es el digest, y ese es idéntico por los dos caminos.

## Para ir más lejos

- Mueva el límite de tamaño del Paso 1 hasta donde le duela: pruebe una etapa final basada en una imagen distroless en vez de scratch, y compare no solo el tamaño sino qué le queda adentro sacando el sistema de archivos con docker create y docker export. Después escanee las tres imágenes (la inflada, la suya y la distroless) con el trivy del laboratorio y anote cuántas vulnerabilidades del sistema operativo reporta cada una. Compare el número de la inflada con el de la suya.
- Haga el experimento que el Paso 2 solo describe: vuelva a construir una imagen distinta, súbala al registro con el mismo tag tienda/pan:v1, y observe que el digest del registro cambió. Después borre un Pod del Deployment fijado por digest y vea que el reemplazo sigue trayendo el contenido viejo, el que usted fijó. Repita el experimento con un Deployment pedido por tag y vea la diferencia con sus propios ojos. Ese es el capítulo entero en dos minutos.
- Genere un inventario de materiales (SBOM) de las dos imágenes candidatas con trivy en formato CycloneDX o SPDX, guárdelos, y después escanee el SBOM en vez de la imagen. Compare el resultado con el escaneo directo. Un SBOM guardado le permite volver a preguntar mañana si esa caja que usted aprobó hoy sigue estando limpia, sin necesidad de que la imagen siga existiendo, y esa es la razón práctica por la que los SBOM existen.
- Rompa el sello a propósito, que es la mejor forma de creerle. Construya una imagen nueva a partir de la aprobada, súbala al registro con otro tag pero al mismo repositorio, y trate de crear un Pod con ella en el-deposito. Va a ser rechazada aunque venga del proveedor aprobado y del repositorio aprobado, porque su digest es otro y ese digest no tiene firma. Después fírmela y vuelva a intentar. Eso le muestra que la unidad que se firma no es el proveedor ni el repositorio: es el contenido exacto.

## Referencias

- Docker documentation, Multi-stage builds. Documents the builder pattern and `COPY --from` used to leave the toolchain behind in Step 1. https://docs.docker.com/build/building/multi-stage/
- Kubernetes documentation, Images. Documents image references by tag and by digest, imagePullPolicy defaults and the imageID field the checks read. https://kubernetes.io/docs/concepts/containers/images/
- Trivy documentation, Container image scanning. Documents the scanners, severity filters and JSON report structure this lab's Step 3 grades against. https://trivy.dev/latest/docs/target/container_image/
- Sigstore documentation, Cosign signing overview. Documents key-pair generation and signing container images with self-managed keys, the exact flow of Step 4. https://docs.sigstore.dev/cosign/signing/overview/
- Kyverno documentation, Verifying image signatures. Documents the verifyImages rule, attestors, mutateDigest and the rekor and ctlog settings this lab needs for an offline signature. https://kyverno.io/docs/policy-types/cluster-policy/verify-images/
- kind documentation, Local registry. Documents running a local registry container alongside a kind cluster and the containerd certs.d configuration the setup writes. https://kind.sigs.k8s.io/docs/user/local-registry/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
