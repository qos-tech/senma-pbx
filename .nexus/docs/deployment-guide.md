# Guia de Implantação e Runtime

## Topologia Docker

| Serviço | Responsabilidade |
|---|---|
| `app` | Apache + PHP 8.4 e aplicação SENMA montada em `/var/www/html/snep`. |
| `db` | MariaDB 10.11 com volume persistente e importação inicial de esquema. |
| `asterisk` | Asterisk 22.11.0 com PJSIP, AGI e ODBC. |
| `provider` | Instância Asterisk independente, apenas para simulação local de tronco PJSIP. |

Os serviços compartilham a rede Compose `mag`, com subnet fixada em `172.28.0.0/16`. Apenas o HTTP da aplicação é publicado no host por padrão; AMI permanece interno.

## Construção e inicialização

```bash
make up
make ps
```

O container `app` gera `includes/setup.conf` quando ausente. O container Asterisk monta `/etc/asterisk` em volume, copia a configuração base, prepara ODBC, provisiona os arquivos PJSIP gerados e cria o symlink para `snep/agi/`.

## Persistência

- `mag-db`: dados MariaDB.
- `asterisk-etc`: configuração Asterisk montada em runtime.
- `mag-asterisk-var`, `mag-asterisk-spool` e `mag-asterisk-log`: estado, spool e logs Asterisk.
- Volumes próprios do `provider`: isolam o simulador do runtime SENMA.

`make reset` remove containers e volumes e é destrutivo. Use somente para recriar o ambiente local de forma intencional.

## Saúde e operação

- `app`: healthcheck HTTP local.
- `db`: `mariadb-admin ping`.
- `asterisk` e `provider`: `asterisk -rx "core show version"`.

Para diagnóstico, use `make logs`, `make ps`, `make shell`, `make db-shell` e `make asterisk-cli`.

## Limites conhecidos

O runtime Docker suporta bootstrap, AGI, PJSIP e validações associadas já documentadas. Qualquer expansão para arquitetura, novo banco ou troca ampla de stack deve ser planejada como fase distinta.
