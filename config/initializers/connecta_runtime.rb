Rails.application.config.after_initialize do
  Connecta::Runtime::Installer.install!
end
