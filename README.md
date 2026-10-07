# Lab IaC — Image Processor en AWS (DEV, QA y PROD)

En este laboratorio de Infraestructura utilizamos terraform para la arquitectura `docs/architecture.mermaid` la cual fue planteada en el ejercicio propuesto .el ejercicio nos lleva al objetivo que el  sistema recibe imágenes, las guarda en S3 y luego las procesa de manera automática. Además, usamos workspaces para tener una versión separada del sistema para el desarrollo, las pruebas y el producción con evidencia las cuales seran adjuntadas.


## Equipo

 el equipo esta conformado por y estos son los roles y aportes que hara cada integrante en en el trabajo 
| Integrante | Rol | Aportes principales |
|---|---|---|
| Angel Eduardo Torres Ruiz | Líder, dueño de la cuenta AWS | Provider, outputs, despliegue y destrucción |
| Sonia Fernanda Caipo Trujillo | Desarrollo | S3, SQS, observabilidad, código de las Lambdas, README |
| Martin Alonso Zavaleta Rodriguez | Desarrollo | Red (VPC), IAM, funciones Lambda, API Gateway |

Para el flujo de trabajo que hemos desarrollado estamos utilizando  GitHub Flow, donde cada tarea se realiza en una rama aparte por el integrante asignado  , luego se crea un Pull Request para que otro integrante revise los cambios y, una vez aprobado los cambios , se hace el merge a main.Ademas implementamos el uso de  Conventional Commits para mantener ordenados los mensajes de los commits.



## Flujo de la aplicación


1. El cliente envía `POST /upload` a API Gateway HTTP API.
2. El API Gateway invoca **upload-lambda** (subredes privadas).
3. upload-lambda valida el tipo (jpg, png, gif, webp) y el tamaño de la imagen , y guarda la imagen en `uploads/` del bucket **S3** a través del **VPC Endpoint de S3**.
4. S3 envía un evento `ObjectCreated` a la cola **SQS** (solo para `uploads/`).
5. SQS dispara **crop-lambda** en lotes de 5 mensajes.
6. crop-lambda descarga la imagen y la recorta a 40x40 con máscara circular (PNG transparente).
7. Guarda el resultado en `processed/`.
8. Si un mensaje llegara a fallar 3 veces pasa a la **DLQ**, que activa una **alarma de CloudWatch** hacia un tópico **SNS**.


## Corrección respecto al diagrama: NAT Gateways

en el diagrama se puede observar que hay 2 NAT Gateways ,pero en nuestro caso las lambdas solo necesitan comunicarse con S3 y SQS y ambos servicios se pueden acceder mediante VPC Endpoints.Por ese motivo decidimos no crear los NAT Gateways.



En el diagrama aparecen 2 NAT Gateways, pero en nuestro caso las Lambdas solo necesitan comunicarse con S3 y SQS, y ambos servicios se pueden acceder mediante VPC Endpoints. Por estos motivos  decidimos no crear los NAT Gateways.

- Un NAT Gateway genera un costo por cada hora que está activo, aunque no tenga tráfico.
- Tener 2 NAT por entorno y 3 entornos (dev, qa y prod) significaría tener 6 NAT Gateways funcionando sin un uso real.
- El Gateway Endpoint para S3 no genera ese costo.

Pero las subredes públicas y el Internet Gateway sí se crean, tal como aparecen en el diagrama.

Otras decisiones para evitar el  costo fueron :
- La notificación de S3 solo filtra uploads/. Así evitamos que las imágenes guardadas en processed/ vuelvan a activar crop-lambda y se genere un bucle infinito.
- Como el versionado está activo, las versiones antiguas se eliminan al día siguiente mediante noncurrent_version_expiration.
- Los log groups se crean con una retención de 14 días para evitar que los logs se acumulen indefinidamente.




## Estructura



.
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


## Despliegue


Sera probado en el sistema operativo  Debian (x86_64).


1. Dependencias de las Lambdas son:
 El crop usa sharp, que trae binarios nativos en Debian x86_64 npm descarga los de Linux x64, que son los mismos que necesita AWS Lambda.
 
 comandos :
npm install --prefix lambda_src/upload --omit=dev
npm install --prefix lambda_src/crop --omit=dev


# 2. Inicializar Terraform
terraform init


# 3. Crear los workspaces (solo la primera vez)
terraform workspace new dev
terraform workspace new qa
terraform workspace new prod


# 4. Desplegar un entorno (repetir con qa y prod)

terraform workspace select dev
terraform apply
terraform output


¡Dato ! No se debe desplegar en el works pace `default' los mapas de variables solo tienen `dev`, `qa` y `prod`, así que Terraform muestra un error a propósito.


## Prueba

```bash
url=$(terraform output -raw upload_url)
bucket=$(terraform output -raw bucket_name)
curl -i -X POST "$url" -F "file=@pruebas/foto.jpg;type=image/jpeg"
aws s3 ls "s3://$bucket/processed/" 
```



Respuesta que se espera obtener : `201` con la ruta `uploads/<uuid>.jpg`. Unos segundos después aparece `processed/<uuid>_circular.png`.


## Destrucción


```bash
terraform workspace select dev
terraform destroy
# repetir con qa y prod
```


Al momento de destruir, AWS tarda varios minutos en nuestro caso fueron tres 3 destrucciones y se tardo al rededor de 1 hora ,en liberar las interfaces de red que Lambda crea dentro de la VPC. Durante ese tiempo Terraform muestra `Still destroying...` en subredes y security groups; es normal y no se debe cancelar (tener paciencia).


## Limitaciones conocidas


- El diagrama indica un máximo de 10 MB, pero AWS Lambda acepta como máximo 6 MB por invocación síncrona. En la práctica se ven , imágenes de más de ~6 MB (o ~4.5 MB si se envían en base64 dentro de un JSON) son rechazadas antes de llegar al código.
- El tópico SNS se logra crear sin suscriptores y las alarma se pueden ver en CloudWatch.


