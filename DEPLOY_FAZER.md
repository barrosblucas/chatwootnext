# Deploy rápido — imagem pronta fazer.ai + liberação premium
#
# 1) cp .env.fazer.example .env  &&  edite senhas / FRONTEND_URL / SECRET_KEY_BASE
# 2) docker compose -f docker-compose.fazer.yml pull
# 3) docker compose -f docker-compose.fazer.yml up -d
# 4) Aguarde o healthcheck do rails (~2–5 min na 1ª subida: migrate)
# 5) docker compose -f docker-compose.fazer.yml exec rails \
#      bundle exec rails runner /scripts/liberar_premium.rb
#
# Imagem: ghcr.io/fazer-ai/chatwoot:latest  (sem build local)
# Compose: docker-compose.fazer.yml
# Env:     .env.fazer.example → .env
# Script:  script/liberar_premium.rb (montado em /scripts)
