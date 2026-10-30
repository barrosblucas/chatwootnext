# Instala no ambiente de teste o mesmo mapeamento de produção que G0Adapter.install! aplica.
# Os specs chamam este helper depois de criar o schema G0 (as tabelas precisam existir).
module Connecta::G0ProductTables
  module_function

  def install!
    Connecta::Runtime::G0Adapter.install!
  end
end
