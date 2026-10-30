class Connecta::V1::TransfersController < Connecta::V1::BaseController
  # Contrato de fio v1 §11: display_id na rota; account_id na query (403 se divergente, ver BaseController).
  def show
    transfer = Connecta::TransferRecord.find(params[:id])
    source = Conversation.find(transfer.source_conversation_id)
    destination = Conversation.find_by(id: transfer.destination_conversation_id)
    render json: {
      id: transfer.id, state: transfer.state, source_conversation_id: source.display_id,
      destination_conversation_id: destination&.display_id, summary_sha256: transfer.summary_sha256,
      summary_length: transfer.summary_length, target_case_version: transfer.target_case_version
    }
  end
end
