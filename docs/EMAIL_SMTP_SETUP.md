# Configuracao de e-mail transacional

Este documento configura o envio de recuperacao de senha do ServiceFlow pelo endereco:

`suporte@cliente.leonardopescouto.com`

## Por que esta configuracao e necessaria

O remetente padrao do Supabase e apenas para testes e possui limite de envio. O projeto ja apresentou `email rate limit exceeded` ao solicitar recuperacao de senha. Em producao, o Supabase recomenda um provedor SMTP proprio.

## Dados SMTP da Hostinger

Use a senha da caixa `suporte@cliente.leonardopescouto.com`. Nao grave essa senha no Git, em arquivos `.env`, nas migrations ou neste manual.

| Campo | Valor |
|---|---|
| Servidor SMTP | `smtp.hostinger.com` |
| Porta recomendada | `465` |
| Seguranca | `SSL/TLS` |
| Usuario | `suporte@cliente.leonardopescouto.com` |
| Remetente | `suporte@cliente.leonardopescouto.com` |
| Nome do remetente | `ServiceFlow` |

Se a conexao na porta 465 falhar, use `587` com `TLS/STARTTLS`. A Hostinger documenta as duas opcoes.

## Configurar no Supabase

1. Abra o projeto Supabase usado pelo ServiceFlow.
2. Va em **Authentication > Emails > SMTP Settings**.
3. Ative o SMTP personalizado.
4. Preencha os campos com a tabela acima.
5. Digite a senha da caixa diretamente no painel do Supabase.
6. Salve e envie um e-mail de teste, se o painel oferecer essa opcao.

O endereco de envio deve ser o mesmo usuario autenticado no SMTP. Nao use a senha do usuario do aplicativo, a senha do banco ou uma chave do Supabase.

## URLs de autenticacao

Em **Authentication > URL Configuration**, confirme:

- **Site URL:** `https://serviceflow.leonardopescouto.com`
- **Redirect URL de recuperacao:** `https://serviceflow.leonardopescouto.com/#/redefinir-senha`

Se o painel exigir padrao, adicione tambem:

`https://serviceflow.leonardopescouto.com/**`

O aplicativo ja envia essa rota no parametro `redirectTo` e mantem a tela de redefinicao aberta enquanto a sessao temporaria do link esta ativa.

## Teste de aceite

1. Aguarde alguns minutos apos salvar o SMTP.
2. Abra **Esqueci minha senha** no ServiceFlow.
3. Solicite o reset para uma conta existente.
4. Confirme a chegada pelo remetente `suporte@cliente.leonardopescouto.com`.
5. Abra o link, defina a nova senha, saia e entre novamente com a nova senha.
6. Verifique a caixa de spam caso a mensagem nao apareca na caixa de entrada.

Se ainda falhar, consulte **Authentication > Logs** no Supabase e confirme no hPanel da Hostinger se a caixa esta ativa e se os registros DNS de e-mail do dominio estao corretos. Para melhorar a entrega, mantenha SPF, DKIM e DMARC publicados conforme os valores fornecidos pela Hostinger.

## Operacao e seguranca

- Nunca enviar a senha SMTP por chat, commit ou ticket.
- Rotacionar a senha da caixa se ela for compartilhada ou exposta.
- Nao usar o remetente de autenticacao para campanhas de marketing.
- Se o dominio ou a caixa mudar, atualizar o Supabase e este documento juntos.
- O `supabase/config.toml` do repositorio nao contem credenciais de producao de proposito.

## Referencias oficiais

- Supabase: custom SMTP e limites do remetente padrao: <https://supabase.com/docs/guides/auth/auth-smtp>
- Hostinger: dados de configuracao SMTP: <https://support.hostinger.com/en/articles/1575756-how-to-get-email-account-configuration-details-for-hostinger-email>
