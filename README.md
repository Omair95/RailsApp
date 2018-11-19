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



