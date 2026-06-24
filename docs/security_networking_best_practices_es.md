# Asset 1: Mejores Prácticas de Redes y Aislamiento de Tráfico SaaS

Esta guía técnica describe cómo diseñar e implementar un entorno de **Cloud Workstations** altamente seguro en Google Cloud Platform (GCP). El objetivo principal de esta guía es **permitir el acceso a servicios SaaS en la nube (GitHub.com y Bitbucket.org) para fines corporativos, mientras se impide estrictamente que los usuarios finales compartan o filtren propiedad intelectual a repositorios o cuentas personales.**

---

## 1. Descripción General de la Arquitectura Segura

Para resolver el desafío técnico donde los dominios como `github.com` y `bitbucket.org` comparten los mismos bloques de direcciones IP públicas tanto para uso personal como corporativo, proponemos una arquitectura basada en **defensa en profundidad**.

> [!NOTE]
> Esta arquitectura es una **idea de implementación y un modelo referencial**. Google Cloud ofrece la flexibilidad para que otros enfoques de control de egreso sean probados y adaptados de acuerdo con las necesidades específicas del cliente. Este ejemplo demuestra el potencial máximo de seguridad del ecosistema GCP.

```mermaid
graph TD
    subgraph Container_Workstation ["Entorno del Desarrollador (Workstation)"]
        Git["Comando Git (HTTPS)"]
        CA["Certificado CA del Proxy instalado"]
    end

    subgraph VPC_GCP ["VPC Privada del Cliente"]
        FW["Firewall GCP: Bloquea Puerto 22 (SSH)"]
        SWP["Cloud Secure Web Proxy (SWP)"]
        TLS["TLS Inspection (Descifrado e Inspección)"]
    end

    subgraph Internet_SaaS ["Servicios Cloud SaaS"]
        NAT["Cloud NAT (IPs Públicas Estáticas Fijas)"]
        GitHubCorp["GitHub Corp: github.com/su-empresa/*"]
        BitbucketCorp["Bitbucket Corp: bitbucket.org/su-empresa/*"]
        PersonalSaaS["SaaS Personal (Push BLOQUEADO)"]
    end

    Git -->|1. Tráfico HTTPS (Puerto 443)| FW
    FW -->|2. Envía al Proxy| SWP
    SWP -->|3. Inspección de Path/Verbo HTTP| TLS
    TLS -->|4. Si es Org Corporativa| NAT
    TLS -.->|4. Si es Org Personal (HTTP 403)| PersonalSaaS
    NAT -->|5. IP Whitelisted| GitHubCorp
    NAT -->|5. IP Whitelisted| BitbucketCorp
```

---

## 2. Elementos Fundamentales de Red y Aislamiento

### 2.1 Red VPC 100% Privada (Sin IPs Públicas)
Las VMs subyacentes de las Cloud Workstations deben aprovisionarse sin direcciones IP públicas externas (`--disable-public-ip-addresses` en la configuración de la workstation). Todo el tráfico de administración de la infraestructura debe ocurrir a través de rutas privadas gestionadas por la red de Google, protegidas por **Identity-Aware Proxy (IAP)**.

### 2.2 Private Google Access (Acceso Privado de Google)
Habilite obligatoriamente **Private Google Access** en la subred de la VPC. Sin IP pública y sin internet directa, las workstations dependen de esta funcionalidad para descargar imágenes base de Artifact Registry, enviar métricas a Cloud Logging y comunicarse internamente con las APIs de GCP utilizando rutas privadas de alto rendimiento.

---

## 3. Estrategia de Restricción de Escritura SaaS (GitHub & Bitbucket)

Para restringir el push de código a espacios de nombres personales manteniendo el acceso corporativo, se emplean tres estrategias de red combinadas:

### 3.1 Cloud Secure Web Proxy (SWP) con TLS Inspection
Un firewall L3/L4 común no puede filtrar rutas de URL HTTPS. En GCP, la mejor práctica para la filtración de capa de aplicación (L7) es el **Cloud Secure Web Proxy (SWP)** integrado con **TLS Inspection**.

1. **Descifrado Seguro**: El SWP intercepta conexiones HTTPS de salida destinadas a GitHub y Bitbucket y las descifra temporalmente utilizando una clave de CA corporativa generada y controlada por el cliente (configurada a través de GCP Certificate Manager / CA Service). El certificado correspondiente se instala como confiable en el contenedor de la workstation.
2. **Inspección de URL Path**: Con el tráfico descifrado, el proxy analiza la URL exacta del repositorio:
   - **Permitido**: `https://github.com/su-empresa/*` (GET y POST)
   - **Permitido**: `https://bitbucket.org/su-empresa/*` (GET y POST)
   - **Bloqueado**: `https://github.com/perfil-personal/*` (Cualquier POST/push)
3. **Bloqueo Selectivo por Verbos HTTP**: Es posible configurar el SWP para permitir comandos de lectura (`GET` para `git clone/pull`) hacia repositorios públicos externos (facilitando la descarga de librerías públicas), pero **bloquear estrictamente cualquier solicitud de escritura** (`POST`, `PUT`, `PATCH`) hacia destinos fuera de la organización corporativa aprobada.

### 3.2 Bloqueo de SSH (Puerto 22) de Salida
El protocolo Git sobre SSH (`git@github.com:...`) viaja a través de un flujo binario cifrado de extremo a extremo sobre el puerto TCP 22. Dado que SSH no tiene el concepto de encabezados o rutas de URL HTTP, evita por completo las reglas de inspección del Secure Web Proxy.
* **Mejor Práctica**: Implementar una regla de Firewall VPC con acción `DENY` y dirección `EGRESS` para impedir cualquier tráfico de salida destinado al puerto `22` en la subred de las workstations.
* **Funcionamento**: Esto obliga al desarrollador y a las herramientas Git del contenedor a utilizar obligatoriamente el transporte HTTPS en el puerto `443`, que pasa por el filtro del proxy L7.

### 3.3 Cloud NAT con IPs Estáticas (IP Whitelisting)
Asocie direcciones IP externas públicas **estáticas** (reservadas previamente en GCP Compute Engine) al gateway **Cloud NAT** de la VPC, en lugar de utilizar asignación dinámica automática de IPs.
* **Beneficio**: Registre estas IPs estáticas de la empresa en las reglas de protección de IP (IP Allow List) de su organización de GitHub Enterprise Cloud o Bitbucket Cloud.
* **Resultado**: El acceso al SaaS corporativo solo se aceptará cuando se origine desde workstations seguras (que salen por el NAT con las IPs registradas). Si un desarrollador intenta acceder a repositorios corporativos desde su máquina personal, el SaaS rechazará la conexión por estar fuera del rango de IPs permitido.

---

## 4. Pros y Contras de Otros Enfoques de Red

Dado que esta guía es un modelo de referencia de posibilidades, a continuación presentamos una comparación de alternativas arquitectónicas de aislamiento de red:

| Arquitectura | Pros | Contras | Recomendación |
| :--- | :--- | :--- | :--- |
| **Secure Web Proxy (SWP) con TLS Inspection** | - Bloqueo absoluto de push a cuentas personales.<br>- Permite clone selectivo de librerías públicas.<br>- Inspección granular. | - Costo fijo del servicio SWP.<br>- Complejidad de administrar la CA y el certificado corporativo en el contenedor. | **Recomendada para entornos corporativos de alta seguridad** que utilizan SaaS Cloud pública. |
| **Aislamiento de Egreso Total (Sin Cloud NAT)** | - Costo cero de red.<br>- Aislamiento físico total de internet. | - Requiere que GitHub/Bitbucket sea 100% self-hosted en red privada (VPN/Interconnect).<br>- Impide la descarga de dependencias y extensiones públicas. | **Ideal si el cliente posee infraestructura híbrida estable** y un servidor Git local privado. |
| **Cloud NAT Tradicional (Sin Proxy L7)** | - Muy bajo costo (~1 USD/mes).<br>- Fácil de configurar.<br>- Permite descargar librerías y extensiones públicas fácilmente. | - No impide el push o clone hacia/desde cuentas o repositorios personales (sin control de ruta de URL). | **Recomendado para fases de POC/Prototipo**, validación de imagen personalizada o entornos menos restrictivos. |

---

## 5. Prácticas de Implementación Recomendadas para el Cliente

Al presentar este proyecto al cliente en la reunión, destaque los siguientes pasos para la construcción de la primera infraestructura de red segura:

1. **Aprovisionar la VPC Privada** y habilitar Private Google Access en la subred principal.
2. **Definir el Alcance de Git**: Evaluar si el cliente utilizará el repositorio en la nube pública (SaaS) o si posee servidores locales en la infraestructura privada.
3. **Evaluar Costos y Riesgos**: Decidir entre la simplicidad de costos del Cloud NAT puro para una POC frente a la protección profesional de fuga de datos del Secure Web Proxy (SWP) para el entorno de producción.
4. **Implementar la Regla de Bloqueo SSH (Puerto 22)** desde el primer día de validación del entorno.
