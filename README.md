## Pasos para ejecutar la POC de carga distribuida

### 1. Creacion de las imagenes Docker de los diferentes modulos

Para poder ejecutar los principales componentes de este modelo (cache-datagrid-application, cache-admin-application y cache-distributed-load-application) es necesario crear sus respectivas imagenes Docker para que de esta manera se puedan descargar en cualquier momento y de manera automatica desde un repositorio de imagenes publico para su correcto uso en los archivos de configuracion YAML de Kubernetes.

Para ello se importa el proyecto como un proyecto Maven en un framework de desarollo Java como Eclipse, posteriormente se compila cada modulo mediante la instruccion de Maven ```maven clean install``` para que se descarguen las dependencias y se forme el JAR. Para que el JAR sea autoejecutable se añade el siguiente plugin en cada archivo pom.xml de cada modulo:

```
<build>
	<plugins>
		<plugin>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-maven-plugin</artifactId>
			<executions>
				<execution>
					<goals>
						<goal>repackage</goal>
					</goals>
				</execution>
			</executions>
		</plugin>
	</plugins>
</build>
```

Para facilitar y simplificar el proceso de formacion de los JARs, se importa el proyecto desde el proyecto padre (cache-server) y se ejecuta el comando de Maven ```maven clean install``` desde el directorio padre que contiene un pom.xml con el orden especifico en el que se deben compilar los modulos.

```
<modules>
	<module>cache-admin-application</module>
	<module>cache-distributed-load-application</module>
	<module>cache-admin-transfer-object</module>
	<module>cache-datagrid-application</module>
	<module>cache-configuration</module>
	<module>cache-event-system-core</module>
</modules>
```

Una vez obtenidos los JARs:

```
cache-admin-application-3.0.1-SNAPSHOT.jar
cache-datagrid-application-3.0.1-SNAPSHOT.jar
cache-distributed-load-application-3.0.1-SNAPSHOT.jar
```

Se procede a crear 1 Dockerfile para cada uno de ellos para la creacion de la imagen Docker, a continuacion se muestra el Dockerfile para el modulo cache-admin-application (todos los Dockerfiles siguen el mismo formato):

```
FROM openjdk:8-jdk-alpine

ADD cache-admin-application-3.0.1-SNAPSHOT.jar cache-admin-application.jar

EXPOSE 8080

CMD java -jar cache-admin-application.jar
```

Ahora este Dockerfile y el archivo JAR correspondiente se suben en Minikube para la creacion de la imagen con el siguiente comando:

```
docker build -t omair95/cache-admin-application .
```

Para guardar las imagenes subidas se usa el repositorio publico Dockerhub de credenciales omair95/everis00, para ello primero se realiza login con el comando:

```
docker login
```

Poniendo las credenciales y finalmente:

```
docker push omair95/cache-admin-application
```

Y esto se repite para los modulos cache-datagrid-application y cache-distributed-load-application.

### 2. Creacion de los pods para los modulos 

Para crear los pods que interactuaran entre ellos es necesario la creacion de archivos YAML para cada modulo, en este archivo se especificaran las replicas de cada pod, los volumenes compartidos, parametros de configuracion, etc. A continuacion se muestra el fichero de configuracion YAML para el modulo cache-datagrid-application (que es el primer modulo que se levanta):

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: cache-datagrid-application
  labels:
    app: cache-datagrid-application
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: cache-datagrid-application
    spec:
      containers:
      - name: cache-datagrid-application
        image: omair95/cache-datagrid-application
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: 5701
        readinessProbe:
          tcpSocket:
            port: 5701
          initialDelaySeconds: 20
          periodSeconds: 5
        livenessProbe:
          tcpSocket:
            port: 5701
          initialDelaySeconds: 20
          periodSeconds: 5
```

En este archivo YAML se especifican, entre otras cosas, las 6 replicas a crear del deployment y la imagen publica a descargar. Para que las diferentes replicas de este pod (cada replica contiene una instancia de Hazelcast) se pueden descubrir entre ellas para formar un cluster de Hazelcast es necesaria la creacion de un servicio de Hazelcast que se muestra a continuacion:

```
apiVersion: v1
kind: Service
metadata:
  labels:
    app: hzc-cluster
  name: hzc-cluster
  namespace: default
spec:
  type: NodePort
  selector:
    app: cache-datagrid-application
  ports:
  - protocol: TCP
    port: 5701
    targetPort: 5701
    nodePort: 30003
```


En este servicio se selecciona el deployment cache-datagrid-application, se escucha del puerto 5701 (es el puerto que publica cada instancia de Hazelcast) y se mapea el puerto 30003 de la maquina host (maquina windows). Ademas de crear el servicio se crea un Role-based access control (RBAC) para otorgar permisos al cluster de hazelcast (deployment cache-datagrid-application) para que pueda acceder al servicio creado, el archivo de configuracion se muestra a continuacion:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: default-cluster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
```

Una vez se han creados los 3 archivos necesarios para levantar el modulo cache-datagrid-application, estos desde fuera de Minikube se levantan en un orden especifico mediante los comandos:


```
kubectl create -f cache-datagrid-application/HazelcastService.yaml
kubectl create -f cache-datagrid-application/rbac.yaml
kubectl create -f cache-datagrid-application/cache-datagrid-application.yaml
```

Consultando los pods creados podemos ver que se han levantado correctamente:

```
$ kubectl get pods -o wide -w
NAME                                          READY     STATUS    RESTARTS   AGE       IP            NODE
cache-datagrid-application-5686769db4-4nv7h   1/1       Running   1          1m        172.17.0.7    minikube
cache-datagrid-application-5686769db4-bjtnx   1/1       Running   1          1m        172.17.0.9    minikube
cache-datagrid-application-5686769db4-ctrwl   1/1       Running   0          1m        172.17.0.6    minikube
cache-datagrid-application-5686769db4-dntgv   1/1       Running   0          1m        172.17.0.5    minikube
cache-datagrid-application-5686769db4-jtqx9   1/1       Running   1          1m        172.17.0.10   minikube
cache-datagrid-application-5686769db4-kggw2   1/1       Running   1          1m        172.17.0.8    minikube
```

Y consultando los logs de algunos de ellos se puede ver que forman el cluster:

```
$ kubectl logs --follow cache-datagrid-application-5686769db4-kggw2

  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::       (v1.5.15.RELEASE)
...
...
...
2018-11-19 12:34:14.160  INFO 1 --- [           main] c.h.s.d.integration.DiscoveryService     : [172.17.0.8]:5701 [dev] [3.1                                                                                           0.5] Kubernetes Discovery: Bearer Token { eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3                                                                                           ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJkZWZhdWx0Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6ImR                                                                                           lZmF1bHQtdG9rZW4tbGp2MjQiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGVmYXVsdCIsImt1YmVybmV0ZXMu                                                                                           aW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjIwYjY4NDZmLWViZjctMTFlOC04MTg4LTA4MDAyNzM3YmQ5NSIsInN1YiI6InN5c3RlbTpzZ                                                                                           XJ2aWNlYWNjb3VudDpkZWZhdWx0OmRlZmF1bHQifQ.RYPQGBHCJaRUfPtOn524FuTaDwCc2CPx8NMsucxZSYgwRbf8AoWUzPVIWW0e1F9_sqvc82FHG1il7dvcVoE                                                                                           3CkAD8N473k9COGxQYhEyj2XrhJWL-sYOqu1vPbSZpjyOcBN_lK2uI2ttRjHWobB_UMd27qItuiARqboaWaXRXGbKG3lahNAap0HQ-eReyy9cbBKOzMZ3A2Wp3-NQ                                                                                           P3Lt6D73mq5On57rRkLQYoTvFQpjr0pLEyatvbKw2J1xdLeA4iq0nu-UIx5H3Wt1hWVMY0p6kFNDwyVK2I0pEx10d738UucRmMdbGXiIkp-Jiu6kjcbJGVJNepGD-                                                                                           5bB6eopJw }
...
...
...
Members {size:6, ver:6} [
        Member [172.17.0.5]:5701 - 4678db34-7e1d-4501-b927-251f58aa84a0
        Member [172.17.0.6]:5701 - f323ee29-bd0d-4cfb-890a-f59e5d976108
        Member [172.17.0.8]:5701 - 97d8ca72-3748-4f49-afd3-ac91034f592f this
        Member [172.17.0.7]:5701 - edb64ecf-6425-4d45-a8a9-e870a3c41c56
        Member [172.17.0.10]:5701 - e9ec2ba5-879e-4449-9076-da4b77a98677
        Member [172.17.0.9]:5701 - 27cc2987-b568-4d7b-a0a8-62562f0a52de
]
...
...
...
```

El segundo modulo a levantar es cache-admin-application, el archivo YAML de este modulo es el siguiente:

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: cache-admin-application
  labels:
    app: cache-admin-application
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: cache-admin-application
    spec:
      containers:
      - name: cache-admin-application
        image: omair95/cache-admin-application
        volumeMounts:
        - mountPath: '/home'
          name: volume
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: 8080
        readinessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 20
          periodSeconds: 5
        livenessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 20
          periodSeconds: 5
      volumes:
      - name: volume
        hostPath:
          path: '/home'
          type: Directory
```

A diferencia del modulo cache-datagrid-application, en éste si que se configura un volumen compartido entre los containers de los pods y la maquina Minikube (se comparte el directorio /home), esto significa que antes de levantar este modulo se han de crear los directorios necesarios con el contenido a subir a Minikube y cambiar sus permisos para que sean accessibles. A continuacion se muestran los directorios con los permisos adequados para este modulo:

```
$ ls -la
ls -la
total 0
drwxrwxrwx  7 root   root   0 Nov 19 12:51 .
drwxr-xr-x 18 root   root   0 Nov 19 12:47 ..
drwxrwxrwx  2 root   root   0 Nov 19 12:51 backup
drwxrwxrwx  2 root   root   0 Nov 19 12:51 data
drwxrwxrwx  3 docker docker 0 Nov 19 12:51 docker
drwxrwxrwx  2 root   root   0 Nov 19 12:51 interchange
drwxrwxrwx  2 root   root   0 Nov 19 12:51 tmp
```

La carpeta interchange contendra los ficheros (estrictamente en formato tar.gz) que queramos subir al cluster de Hazelcast, para ellos creamos un fichero data.tar.gz que contiene una carpeta service, que a su vez contendra el archivo en question a subir, y un archivo MANIFEST.yml.

Ahora ya se puede levantar el modulo cache-admin-application con su archivo YAML, observando los logs de cualquiera de sus 2 pods se puede ver que se ha levantado correctamente:

```
$ kubectl get pods -o wide
NAME                                          READY     STATUS    RESTARTS   AGE       IP            NODE
cache-admin-application-d5646d6cc-kmz24       0/1       Running   4          2m        172.17.0.11   minikube
cache-admin-application-d5646d6cc-mbml6       0/1       Running   4          2m        172.17.0.12   minikube
cache-datagrid-application-5686769db4-4fdxn   1/1       Running   2          7m        172.17.0.8    minikube
cache-datagrid-application-5686769db4-7mm22   1/1       Running   2          7m        172.17.0.9    minikube
cache-datagrid-application-5686769db4-9tzzb   1/1       Running   2          7m        172.17.0.10   minikube
cache-datagrid-application-5686769db4-n592s   1/1       Running   0          7m        172.17.0.5    minikube
cache-datagrid-application-5686769db4-qbhpf   1/1       Running   0          7m        172.17.0.6    minikube
cache-datagrid-application-5686769db4-z8jmv   1/1       Running   2          7m        172.17.0.7    minikube

miqbalak@BCN-236MM12 MINGW64 ~/Documents/cache-distribuida/cache-server (feature/build-k8s-cluster)
$ kubectl logs --follow cache-admin-application-d5646d6cc-mbml6
...
...
...
2018-11-19 13:46:19.105  INFO cache-admin-application-d5646d6cc-mbml6 --- [lient_0.event-2] c.h.c.s.i.ClientMembershipListener       : hz.client_0 [dev] [3.10.5]

Members [6] {
        Member [172.17.0.5]:5701 - 1c4e4d3b-1024-4727-987f-0def3582ffc0
        Member [172.17.0.6]:5701 - 6dd335dd-5ab8-4102-af60-7ba5d24ef331
        Member [172.17.0.8]:5701 - a685e768-dd7e-4909-8b02-b55d902bd703
        Member [172.17.0.7]:5701 - 05814bf3-4537-4341-a85d-fc172697753a
        Member [172.17.0.9]:5701 - 75390644-9b1a-49a8-9a8b-dc56118146c5
        Member [172.17.0.10]:5701 - caba8e76-7be2-4c68-82dd-8843faef280f
}
...
...
```

Ahora se levanta el ultimo modulo cache-distributed-load-application con su archivo YAML:

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: cache-distributed-load-application
  labels:
    app: cache-distributed-load-application
spec:
  replicas: 10
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: cache-distributed-load-application
    spec:
      containers:
      - name: cache-distributed-load-application
        image: omair95/cache-distributed-load-application
        volumeMounts:
        - mountPath: '/home'
          name: volume
        imagePullPolicy: IfNotPresent
      volumes:
      - name: volume
        hostPath:
          path: '/home'
          type: Directory
```

Ya se pueden ver los 3 modulos levantados con sus respectivas replicas:

```
$ kubectl get pods -o wide -w
NAME                                                  READY     STATUS    RESTARTS   AGE       IP            NODE
cache-admin-application-d5646d6cc-kmz24               1/1       Running   5          5m        172.17.0.11   minikube
cache-admin-application-d5646d6cc-mbml6               1/1       Running   6          5m        172.17.0.12   minikube
cache-datagrid-application-5686769db4-4fdxn           1/1       Running   2          10m       172.17.0.8    minikube
cache-datagrid-application-5686769db4-7mm22           1/1       Running   2          10m       172.17.0.9    minikube
cache-datagrid-application-5686769db4-9tzzb           1/1       Running   2          10m       172.17.0.10   minikube
cache-datagrid-application-5686769db4-n592s           1/1       Running   0          10m       172.17.0.5    minikube
cache-datagrid-application-5686769db4-qbhpf           1/1       Running   0          10m       172.17.0.6    minikube
cache-datagrid-application-5686769db4-z8jmv           1/1       Running   2          10m       172.17.0.7    minikube
cache-distributed-load-application-7f7ff8ccb7-fvnzq   1/1       Running   0          10s       172.17.0.13   minikube
cache-distributed-load-application-7f7ff8ccb7-scv6p   1/1       Running   0          10s       172.17.0.14   minikube
cache-distributed-load-application-7f7ff8ccb7-fhd65   1/1       Running   0          10s       172.17.0.15   minikube
cache-distributed-load-application-7f7ff8ccb7-fdgfp   1/1       Running   0          10s       172.17.0.16   minikube
cache-distributed-load-application-7f7ff8ccb7-oifjc   1/1       Running   0          10s       172.17.0.17   minikube
cache-distributed-load-application-7f7ff8ccb7-ithjf   1/1       Running   0          10s       172.17.0.18   minikube
cache-distributed-load-application-7f7ff8ccb7-clapq   1/1       Running   0          10s       172.17.0.19   minikube
cache-distributed-load-application-7f7ff8ccb7-eritf   1/1       Running   0          10s       172.17.0.20   minikube
cache-distributed-load-application-7f7ff8ccb7-pqoie   1/1       Running   0          10s       172.17.0.21   minikube
cache-distributed-load-application-7f7ff8ccb7-aksjf   1/1       Running   0          10s       172.17.0.2   minikube
```

### 3. Comprobacion de la correcta subida de los ficheros al cluster

Una vez que se pone el fichero tar.gz a subir en el directorio /home/interchange, automaticamente el modulo cache-admin-application detecta el evento y lo prepara para subirlo, esto se puede ver en los logs:

```
$ kubectl logs --follow cache-admin-application-d5646d6cc-kmz24

  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
...
...
...
Members [6] {
        Member [172.17.0.5]:5701 - 1c4e4d3b-1024-4727-987f-0def3582ffc0
        Member [172.17.0.6]:5701 - 6dd335dd-5ab8-4102-af60-7ba5d24ef331
        Member [172.17.0.8]:5701 - a685e768-dd7e-4909-8b02-b55d902bd703
        Member [172.17.0.7]:5701 - 05814bf3-4537-4341-a85d-fc172697753a
        Member [172.17.0.9]:5701 - 75390644-9b1a-49a8-9a8b-dc56118146c5
        Member [172.17.0.10]:5701 - caba8e76-7be2-4c68-82dd-8843faef280f
}
...
...
...
2018-11-19 13:47:38.257  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Receiving new event:CON.000005
2018-11-19 13:47:42.741  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .c.l.s.i.DistributedLoadHazelcastService : Saving new event CON.000005 with 1 load tasks
2018-11-19 13:47:43.144 DEBUG cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .c.l.s.i.DistributedLoadHazelcastService : Saving and publishing task: [taskId=16e2f7f7-f063-43da-8332-427408a91cf7, eventId=CON.000005] for the following target: Manager: service
2018-11-19 13:47:50.599  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:47:50.907  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .l.s.e.LoadEventStatusInProgressStrategy : Locking and Applying strategy for event: CON.000005
2018-11-19 13:48:20.597  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:48:20.626  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .l.s.e.LoadEventStatusInProgressStrategy : Locking and Applying strategy for event: CON.000005
2018-11-19 13:48:50.598  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:48:50.630  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .l.s.e.LoadEventStatusInProgressStrategy : Locking and Applying strategy for event: CON.000005
2018-11-19 13:49:20.597  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:49:20.644  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .l.s.e.LoadEventStatusInProgressStrategy : Locking and Applying strategy for event: CON.000005
...
...
2018-11-19 13:49:20.758  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.m.ManifestEventCreator         : Loading event:LoadEvent [eventId=CON.000005, type=INC, createDate=java.util.GregorianCalendar[time=1542635360758,areFieldsSet=true,areAllFieldsSet=true,lenient=true,zone=sun.util.calendar.ZoneInfo[id="GMT",offset=0,dstSavings=0,useDaylight=false,transitions=0,lastRule=null],firstDayOfWeek=1,minimalDaysInFirstWeek=1,ERA=1,YEAR=2018,MONTH=10,WEEK_OF_YEAR=47,WEEK_OF_MONTH=4,DAY_OF_MONTH=19,DAY_OF_YEAR=323,DAY_OF_WEEK=2,DAY_OF_WEEK_IN_MONTH=3,AM_PM=1,HOUR=1,HOUR_OF_DAY=13,MINUTE=49,SECOND=20,MILLISECOND=758,ZONE_OFFSET=0,DST_OFFSET=0], updateDate=java.util.GregorianCalendar[time=1542635360758,areFieldsSet=true,areAllFieldsSet=true,lenient=true,zone=sun.util.calendar.ZoneInfo[id="GMT",offset=0,dstSavings=0,useDaylight=false,transitions=0,lastRule=null],firstDayOfWeek=1,minimalDaysInFirstWeek=1,ERA=1,YEAR=2018,MONTH=10,WEEK_OF_YEAR=47,WEEK_OF_MONTH=4,DAY_OF_MONTH=19,DAY_OF_YEAR=323,DAY_OF_WEEK=2,DAY_OF_WEEK_IN_MONTH=3,AM_PM=1,HOUR=1,HOUR_OF_DAY=13,MINUTE=49,SECOND=20,MILLISECOND=758,ZONE_OFFSET=0,DST_OFFSET=0], status=CREATED, fileEvent=null]
2018-11-19 13:49:20.759  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.m.ManifestEventCreator         : Manifest id :CON.000005, target :ARQ,manager :service, segments empty
2018-11-19 13:49:20.760  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.m.ManifestEventCreator         : Creating new task:LoadTask [id=[taskId=ec9b444a-4e5e-40dd-99b6-788a69ec8a2c, eventId=CON.000005], manager=service, segment=null, createdDate=java.util.GregorianCalendar[time=1542635360760,areFieldsSet=true,areAllFieldsSet=true,lenient=true,zone=sun.util.calendar.ZoneInfo[id="GMT",offset=0,dstSavings=0,useDaylight=false,transitions=0,lastRule=null],firstDayOfWeek=1,minimalDaysInFirstWeek=1,ERA=1,YEAR=2018,MONTH=10,WEEK_OF_YEAR=47,WEEK_OF_MONTH=4,DAY_OF_MONTH=19,DAY_OF_YEAR=323,DAY_OF_WEEK=2,DAY_OF_WEEK_IN_MONTH=3,AM_PM=1,HOUR=1,HOUR_OF_DAY=13,MINUTE=49,SECOND=20,MILLISECOND=760,ZONE_OFFSET=0,DST_OFFSET=0], updateDate=java.util.GregorianCalendar[time=1542635360760,areFieldsSet=true,areAllFieldsSet=true,lenient=true,zone=sun.util.calendar.ZoneInfo[id="GMT",offset=0,dstSavings=0,useDaylight=false,transitions=0,lastRule=null],firstDayOfWeek=1,minimalDaysInFirstWeek=1,ERA=1,YEAR=2018,MONTH=10,WEEK_OF_YEAR=47,WEEK_OF_MONTH=4,DAY_OF_MONTH=19,DAY_OF_YEAR=323,DAY_OF_WEEK=2,DAY_OF_WEEK_IN_MONTH=3,AM_PM=1,HOUR=1,HOUR_OF_DAY=13,MINUTE=49,SECOND=20,MILLISECOND=760,ZONE_OFFSET=0,DST_OFFSET=0], type=INC, status=CREATED, count=0]
2018-11-19 13:49:20.785  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Receiving new event:CON.000005
2018-11-19 13:49:20.859  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : The eventId CON.000005 is not going to be processed
2018-11-19 13:49:50.598  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:49:50.616  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .l.a.c.l.s.e.LoadEventStatusDoneStrategy : Locking and Applying strategy for event: CON.000005
2018-11-19 13:49:50.655  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] .c.l.s.i.DistributedLoadHazelcastService : Archiving event CON.000005
2018-11-19 13:50:20.597  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:50:50.598  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:51:20.597  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:51:20.606  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Directory /home/interchange doesn't contains tar.gz files to process
2018-11-19 13:51:50.597  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:52:20.596  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
2018-11-19 13:52:50.596  INFO cache-admin-application-d5646d6cc-kmz24 --- [pool-2-thread-1] e.l.a.c.l.h.LoadEventHandler             : Checking event and task status
...
...
...
```

Ahora se pueden consultar estos eventos procesados por el modulo cache-admin-application desde fuera de Minikube, para ello se crea el siguiente servicio que externaliza los pods del modulo cache-admin-application para que se puedan lanzar peticiones HTTP para realizar consultas:

```
apiVersion: v1
kind: Service
metadata:
  labels:
    app: admin
  name: admin
  namespace: default
spec:
  type: NodePort
  selector:
    app: cache-admin-application
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
    nodePort: 30004
```

Una vez creado, realizamos las siguientes consultas para comprobar el estado del cluster:

```
$ curl 192.168.99.100:30004/archived_events
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   113    0   113    0     0    180      0 --:--:-- --:--:-- --:--:--   180[{"eventId":"CON.000005","type":"INC","createDate":1542635257637,"updateDate":1542635908944,"status":"ARCHIVED"}]
```

Y podemos ver que efectivamente se ha creado un evento a partir del fichero tar.gz que se habia puesto anteriormente en el directorio /home/interchange. 
