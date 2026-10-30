# Base dos registros do spike G0 (tabelas connecta_g0_*). Não é modelo de produto: o schema existe só no banco de teste G0.
class Connecta::Scope::BaseRecord < ApplicationRecord
  self.abstract_class = true
end
