# Diretrizes de Segurança de Desenvolvimento (AGENTS.md)

Este documento contém as regras de negócio e os princípios de segurança obrigatórios que devem ser seguidos por todos os desenvolvedores neste ambiente. O objetivo é garantir que toda aplicação desenvolvida a partir desta workstation siga uma base sólida de **Segurança por Padrão (Secure by Default)**.

---

## 1. Princípios Fundamentais de Segurança

*   **Menor Privilégio (Least Privilege):** Entidades (usuários, serviços) devem ter apenas as permissões estritamente necessárias para realizar suas funções de negócio. Não utilize credenciais com permissões amplas (como `Owner` ou `admin`) para desenvolvimento ou testes cotidianos.
*   **Defesa em Profundidade (Defense in Depth):** Implemente múltiplos controles de segurança em camadas. A falha de um único controle de segurança não deve comprometer a integridade total do sistema.
*   **Nunca Confiar, Sempre Verificar (Zero Trust):** Trate todas as requisições, sejam elas de origem interna ou externa, como potencialmente não confiáveis. Autentique e autorize explicitamente cada acesso a recursos.
*   **Segurança por Padrão (Secure by Default):** As configurações padrão do sistema, bibliotecas e ambientes devem ser configuradas para o nível mais restrito de segurança.

---

## 2. Regras de Autenticação e Autorização

*   **Autenticação Forte:**
    *   Exija Autenticação Multifator (MFA) para todas as contas e integrações com dados sensíveis ou painéis administrativos.
    *   Configure mecanismos de bloqueio de conta temporário após múltiplas tentativas consecutivas de login falhas.
*   **Armazenamento de Senhas:**
    *   **NUNCA** armazene senhas em texto plano.
    *   Senhas de usuários devem ser salvas usando algoritmos de hashing criptográfico forte e com salt único por registro (utilizando **Argon2** ou **bcrypt**).
*   **Controle de Acesso Baseado em Papéis (RBAC):**
    *   O acesso a endpoints e recursos da aplicação deve ser condicionado ao papel do usuário.
    *   Utilize decorators, middlewares ou interceptadores estruturados (ex: `@require_role('admin')`) para proteger de forma centralizada todas as rotas da API.
*   **Gerenciamento de Sessão e Tokens:**
    *   Utilize tokens de curta duração (ex: JWT) para autenticar requisições de API.
    *   Para renovação de acesso, implemente mecanismos de *refresh token* seguros, armazenados estritamente em cookies com a flag `HttpOnly` ativa para prevenir roubos via scripts maliciosos.
    *   Sempre valide a assinatura e a expiração do token em todas as chamadas de API.

---

## 3. Manipulação e Proteção de Dados

*   **Validação de Entrada (Input Validation):**
    *   Valide, sanitize e escape rigorosamente todos os dados provenientes dos usuários ou de sistemas externos antes de processá-los. Isso previne ataques clássicos como SQL Injection (SQLi), Cross-Site Scripting (XSS) e Command Injection.
    *   Utilize bibliotecas de validação de esquema fortes e tipadas (como **Pydantic** para Python ou **Zod** para TypeScript) para todos os payloads de APIs.
*   **Dados Sensíveis e Informações Pessoais (PII):**
    *   **NUNCA registre dados sensíveis em logs** (como CPFs, senhas, tokens de autenticação ou chaves de API). Caso o registro seja estritamente necessário para depuração, mascare as informações antes de salvar nos logs.
    *   Identifique e classifique os dados sensíveis no código-fonte por meio de anotações ou tipos de dados específicos.
*   **Criptografia:**
    *   Todo o tráfego de rede da aplicação em produção deve trafegar obrigatoriamente sobre TLS 1.2 ou superior (HTTPS, WSS).
    *   Dados sensíveis armazenados em banco de dados (dados em repouso) devem ser criptografados.

---

## 4. Desenvolvimento Seguro (Secure SDLC)

*   **Gerenciamento de Segredos (Secrets Management):**
    *   **É TERMINANTEMENTE PROIBIDO "hardcodar" segredos** (chaves de API, senhas de banco de dados, chaves de criptografia, etc.) no código-fonte ou em arquivos de ambiente versionados (como `.env`).
    *   Utilize um gerenciador de segredos seguro e homologado (como **Google Secret Manager**, AWS Secrets Manager ou HashiCorp Vault) para injetar segredos no ambiente de execução das aplicações de forma segura.
*   **Análise de Dependências:**
    *   Mantenha todas as dependências do projeto atualizadas.
    *   Realize varreduras e escaneamentos de segurança regulares (usando ferramentas como **OSV-Scanner** ou `npm audit`) para identificar e mitigar vulnerabilidades conhecidas em bibliotecas terceiras.
*   **Tratamento de Erros:**
    *   Mensagens de erro genéricas e seguras devem ser retornadas ao cliente final para evitar o vazamento de detalhes de implementação interna (como stack traces de banco de dados ou caminhos de arquivos).
    *   Registre detalhes técnicos completos e o stack trace do erro apenas nos logs do servidor, os quais devem ter acesso altamente restrito.
