# Lab IaC — Image Processor en AWS (DEV, QA y PROD)

En este laboratorio de Infraestructura utilizamos terraform para la arquitectura `docs/architecture.mermaid` la cual fue planteada en el ejercicio propuesto .El ejercicio nos lleva al objetivo que el  sistema recibe imágenes, las guarda en S3 y luego las procesa de manera automática. Además, usamos workspaces para tener una versión separada del sistema para el desarrollo, las pruebas y el producción con evidencia las cuales seran adjuntadas.


## Equipo

 el equipo esta conformado por los siguiente integrantes :
 
Integrantes: 

 Angel Eduardo Torres Ruiz ->  Líder, dueño de la cuenta AWS

 Sonia Fernanda Caipo Trujillo -> Desarrollo- Documentador

 Martin Alonso Zavaleta Rodriguez -> Desarrollo -Documentador


Para el flujo de trabajo que hemos desarrollado estamos utilizando  GitHub Flow, donde cada tarea se realiza en una rama aparte por el integrante asignado  , luego se crea un Pull Request para que otro integrante revise los cambios y, una vez aprobado los cambios , se hace el merge a main.Ademas implementamos el uso de  Conventional Commits para mantener ordenados los mensajes de los commits.



## Flujo de la aplicación


1. El cliente envía `POST /upload` a API Gateway HTTP API.
2. El API Gateway invoca **upload-lambda** (subredes privadas).
3. upload-lambda valida el tipo (jpg, png, gif, webp) y el tamaño de la imagen , y guarda la imagen en `uploads/` del bucket **S3** a través del **VPC Endpoint de S3**.
4. S3 envía un evento `ObjectCreated` a la cola **SQS** (solo para `uploads/`).
5. SQS dispara **crop-lambda** en lotes de 5 mensajes.
6. crop-lambda descarga la imagen y la recorta a 40x40 con máscara circular (PNG transparente).
7. Guarda el resultado en `processed/`.


## Corrección respecto al diagrama: NAT Gateways

en el diagrama se puede observar que hay 2 NAT Gateways ,pero en nuestro caso las lambdas solo necesitan comunicarse con S3 y SQS y ambos servicios se pueden acceder mediante VPC Endpoints.Por ese motivo decidimos no crear los NAT Gateways por el costo que genera solo su existencia .


- Un NAT Gateway genera un costo por cada hora que está activo, aunque no tenga tráfico.
- Tener 2 NAT por entorno y 3 entornos (dev, qa y prod) significaría tener 6 NAT Gateways funcionando sin un uso real.
- El Gateway Endpoint para S3 no genera ese costo.

Pero las subredes públicas y el Internet Gateway sí se crean, tal como aparecen en el diagrama.

Otras decisiones que tomamos para evitar el  costo fueron :
- La notificación de S3 solo filtra uploads/. Así evitamos que las imágenes guardadas en processed/ vuelvan a activar crop-lambda y se genere un bucle infinito.
- Como el versionado está activo, las versiones antiguas se eliminan al día siguiente mediante noncurrent_version_expiration para evitar pagar por el almacenamiento que genera gastos.
- Los log groups se crean con una retención de 14 días para evitar que los logs se acumulen indefinidamente.




## Estructura



Grupo_08-Tarea_S5

├── providers.tf        # provider de AWS (credenciales vía `aws configure`)

├── variables.tf        # variables; las del API son mapas por workspace

├── terraform.tfvars

├── storage.tf          # S3: uploads/ y processed/

├── queue.tf            # SQS, DLQ y notificación S3 -> SQS

├── network.tf          # VPC, subredes, IGW, security groups y VPC endpoints

├── iam.tf              # roles de mínimo privilegio

├── observability.tf    # log groups, SNS y alarma de la DLQ

├── lambda.tf           # upload-lambda, crop-lambda y trigger de SQS

├── api.tf              # API Gateway HTTP API

├── outputs.tf

├── lambda_src/

│   ├── upload/         # Node.js 20: recibe y valida la imagen

│   └── crop/           # Node.js 20 + sharp: recorte circular 40x40

└── docs/architecture.mermaid



## Requisitos


- Terraform
- AWS CLI v2 configurado con `aws configure` (región `us-east-1`)
- Node.js >= 18.17 y npm
- Debian (o cualquier Linux) en x86_64


## Despliegue:

Sera probado en el sistema operativo  Debian (x86_64) y en una mac (Alonso).

### 1. Dependencias de las Lambdas son:
 
 El crop usa sharp, que trae binarios nativos en Debian x86_64 npm descarga los de Linux x64, que son los mismos que necesita AWS Lambda.
 
- comandos :

npm install --prefix lambda_src/upload --omit=dev

npm install --prefix lambda_src/crop --omit=dev


### 2. Inicializar Terraform

terraform init


### 3. Crear los workspaces (solo la primera vez)

terraform workspace new dev

terraform workspace new qa

terraform workspace new prod


### 4. Desplegar un entorno (repetir con qa y prod)

terraform workspace select dev
terraform apply
terraform output



## Prueba


url=$(terraform output -raw upload_url)

bucket=$(terraform output -raw bucket_name)

curl -i -X POST "$url" -F "file=@pruebas/foto.jpg;type=image/jpeg"

aws s3 ls "s3://$bucket/processed/" 



- Respuesta que se espera obtener : `201` con la ruta `uploads/<uuid>.jpg`. Unos segundos después aparece `processed/<uuid>_circular.png`.


## Destrucción

### repetir con qa y prod

terraform workspace select dev

terraform destroy


- Al momento de destruir, AWS tarda varios minutos (de 15 a 20 minutos ) en nuestro caso fueron tres 3 destrucciones y se tardo al rededor de 1 hora y media ,en liberar las interfaces de red que Lambda crea dentro de la VPC. Durante ese tiempo Terraform muestra `Still destroying...` en subredes y security groups; es normal y no se debe cancelar.


## observaciones identificadas dentro del proyecto

- El diagrama indica un máximo de 10 MB, pero en AWS Lambda acepta como máximo 6 MB por invocación síncrona. En la practica se ven que si las imágenes son más de ~6 MB son rechazadas antes de llegar al código.

