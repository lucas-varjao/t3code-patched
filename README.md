# t3code-patched

Automação para produzir builds do T3 Code Nightly com um patch local mínimo.

## Patch mantido

`patches/cursor-ask-question.patch`

Adiciona um fallback MCP `t3-code: ask_question` para sessões Cursor ACP,
reutilizando a UI nativa de perguntas do T3 Code.

## Estratégia

1. Descobrir a nightly oficial mais recente.
2. Fazer checkout da tag oficial.
3. Aplicar o patch local.
4. Executar testes e typecheck.
5. Produzir Desktop Linux x64 e CLI Linux x64.
6. Publicar ambos como uma release correspondente à mesma versão upstream.

Se o patch deixar de aplicar, o pipeline deve falhar e nenhuma atualização
patched deve ser publicada.
