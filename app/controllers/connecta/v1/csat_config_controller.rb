# Modo da pesquisa de satisfação por inbox (Fase 2, painel do município).
# O WP chama o fork (HMAC) quando o admin escolhe o modo: "whatsapp" (o
# cidadão digita a nota de 1–5 no WhatsApp), "link" (página pública) ou
# "off" (sem pesquisa). Só inbox marcada em `connecta_scoped_inboxes`;
# `account_id` é validado no BaseController. Idempotente.
class Connecta::V1::CsatConfigController < Connecta::V1::BaseController
  MODES = %w[whatsapp link off].freeze
  DEFAULT_WINDOW_MINUTES = 60

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: 'inbox_not_enforced' }, status: :not_found
  end

  def update
    inbox = enforced_inbox!
    mode = config_params[:mode].to_s
    return render_invalid_mode unless MODES.include?(mode)

    window_minutes = parse_window_minutes
    return render_invalid_window_minutes unless window_minutes

    apply_csat_config!(inbox, mode, window_minutes)

    render json: applied_config(inbox, mode, window_minutes)
  end

  private

  def render_invalid_mode
    render json: { error: 'invalid_mode', allowed: MODES }, status: :unprocessable_entity
  end

  def render_invalid_window_minutes
    render json: { error: 'invalid_window_minutes' }, status: :unprocessable_entity
  end

  def apply_csat_config!(inbox, mode, window_minutes)
    inbox.update!(
      csat_survey_enabled: mode != 'off',
      csat_config: (inbox.csat_config || {}).merge(
        'mode' => mode,
        'display_type' => 'star',
        'disable_feedback' => true,
        'window_minutes' => window_minutes
      )
    )
  end

  def applied_config(inbox, mode, window_minutes)
    {
      inbox_id: inbox.id,
      mode: mode,
      window_minutes: window_minutes,
      csat_survey_enabled: inbox.csat_survey_enabled,
      display_type: 'star',
      disable_feedback: true
    }
  end

  # Inbox da conta configurada E marcada no Connecta; fora disso 404 sem
  # vazar se a inbox existe.
  def enforced_inbox!
    inbox_id = config_params[:inbox_id]
    account_id = Connecta::Runtime::Feature.current_account_id!
    inbox = Inbox.find_by!(id: inbox_id, account_id: account_id)
    raise ActiveRecord::RecordNotFound unless Connecta::Scope::CsatPolicy.scoped_inbox?(inbox.id)

    inbox
  end

  def config_params
    params.permit(:account_id, :inbox_id, :mode, :window_minutes)
  end

  def parse_window_minutes
    raw = config_params[:window_minutes]
    return DEFAULT_WINDOW_MINUTES if raw.nil?

    # JSON entrega Integer (base explícita estouraria); form entrega String.
    minutes = raw.is_a?(Numeric) ? raw.to_i : Integer(raw.to_s.strip, 10)
    minutes.positive? ? minutes : nil
  rescue ArgumentError, TypeError
    nil
  end
end
