# t3code-patched

Automação para produzir builds do T3 Code Nightly com um patch local mínimo.

## Patch mantido

`patches/cursor-ask-question.patch` + `patches/cursor-ask-question-async.patch`

Adiciona um fallback MCP assíncrono para sessões Cursor ACP, reutilizando a UI nativa de perguntas do T3 Code. `ask_question` abre a pergunta e retorna imediatamente um `requestId`; `wait_for_answer` faz long-poll de no máximo 45 segundos e é repetido enquanto a resposta estiver pendente. Assim nenhuma chamada MCP individual permanece aberta até o timeout de aproximadamente 60 segundos do cliente MCP do Cursor.

## Estratégia

1. Descobrir a nightly oficial mais recente.
2. Fazer checkout da tag oficial.
3. Aplicar o patch local.
4. Executar testes e typecheck.
5. Produzir Desktop Linux x64 e CLI Linux x64.
6. Publicar ambos como uma release correspondente à mesma versão upstream.

Se o patch deixar de aplicar, o pipeline deve falhar e nenhuma atualização
patched deve ser publicada.
