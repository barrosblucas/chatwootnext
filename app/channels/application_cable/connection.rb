class ApplicationCable::Connection < ActionCable::Connection::Base
  identified_by :connecta_user_id

  # This identifier is only used to close a user's sockets after an ACL revoke.
  # RoomChannel still authenticates each subscription with the normal user id and pubsub token.
  def connect
    self.connecta_user_id = request.params[:connecta_user_id].presence || 'anonymous'
  end
end
