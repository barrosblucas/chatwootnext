# Changelog 2026-10-26

## Changed
- `deploy/e2e/compose.yml`: `wp` e `fork-web` publicados em `192.168.1.32` (LAN) em vez de `127.0.0.1`, para teste de outro dispositivo. Baileys, Redis e bancos seguem só em loopback.
- `deploy/e2e/fork.env` (ignorado pelo git, local): `FRONTEND_URL=http://192.168.1.32:3006`.

## Docs
- `deploy/e2e/README.md`: URLs e portas atualizadas para a LAN, com aviso de que a exposição é só para teste com credenciais sintéticas.
- `deploy/e2e/README.md`: painel corrigido para `http://192.168.1.32:3007/login` (serviço `wp-admin`, Next separado; a API `wp`:3005 não é o painel). Registrado o admin municipal `admin@bandeirantes.ms.gov.br` (sem senha).

## Fixed
- WhatsApp/Baileys: o QR era apagado no evento `close` (QR expira em ~60 s). `Whatsapp::BaileysHandlers::ConnectionUpdate` substituía todo o `provider_connection` e gravava `qr_data_url` como `nil` quando o evento não trazia QR. Agora mescla: mantém o último `qr_data_url` enquanto a conexão não estiver `open` e grava `qr_updated_at` a cada QR novo (`app/services/whatsapp/baileys_handlers/connection_update.rb`).
- `WhatsappLinkDeviceModal.vue`: com `connection === 'close'` e QR presente, o modal mostra o QR em vez de "Vincular dispositivo".
- Validação: spec `incoming_message_baileys_service_spec.rb` 100 exemplos, 0 falhas (banco G0); RuboCop limpo. Ciclo real no fork com número sintético de teste: 5 renovações de QR em ~3 min e QR preservado após `close`. Worker `fork-worker` precisou ser recriado com a imagem nova (antes gravava o formato antigo).
